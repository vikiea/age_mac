/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"filippo.io/age"
	"filippo.io/age/armor"
)

const (
	maxConcurrency = 12
	defaultKeyType = "post-quantum"
)

var emitMu sync.Mutex
var outputPathMu sync.Mutex

type fileSpec struct {
	Path string `json:"path"`
	Name string `json:"name"`
}

type event struct {
	Event     string   `json:"event"`
	Phase     string   `json:"phase,omitempty"`
	Progress  float64  `json:"progress,omitempty"`
	Processed int      `json:"processed,omitempty"`
	Total     int      `json:"total,omitempty"`
	Success   int      `json:"success,omitempty"`
	Fail      int      `json:"fail,omitempty"`
	Output    string   `json:"output,omitempty"`
	Outputs   []string `json:"outputs,omitempty"`
	Message   string   `json:"message,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		fail(errors.New("missing command"))
	}

	var err error
	switch os.Args[1] {
	case "keygen":
		err = keygen(os.Args[2:])
	case "encrypt-batch":
		err = encryptBatch(os.Args[2:])
	case "encrypt-separate":
		err = encryptSeparate(os.Args[2:])
	case "decrypt":
		err = decryptFiles(os.Args[2:])
	default:
		err = fmt.Errorf("unknown command: %s", os.Args[1])
	}
	if err != nil {
		fail(err)
	}
}

func fail(err error) {
	emit(event{Event: "error", Message: err.Error()})
	os.Exit(1)
}

func emit(e event) {
	data, _ := json.Marshal(e)
	emitMu.Lock()
	defer emitMu.Unlock()
	fmt.Println(string(data))
}

func keygen(args []string) error {
	fs := flag.NewFlagSet("keygen", flag.ContinueOnError)
	keyType := fs.String("type", defaultKeyType, "post-quantum or x25519")
	if err := fs.Parse(args); err != nil {
		return err
	}

	publicKey, privateKey, err := generateKeyPair(*keyType)
	if err != nil {
		return err
	}
	payload := map[string]string{
		"event":      "keypair",
		"publicKey":  publicKey,
		"privateKey": privateKey,
	}
	data, _ := json.Marshal(payload)
	fmt.Println(string(data))
	return nil
}

func generateKeyPair(keyType string) (publicKey string, privateKey string, err error) {
	switch keyType {
	case "post-quantum":
		identity, err := age.GenerateHybridIdentity()
		if err != nil {
			return "", "", fmt.Errorf("failed to generate post-quantum key pair: %w", err)
		}
		return identity.Recipient().String(), identity.String(), nil
	case "x25519":
		identity, err := age.GenerateX25519Identity()
		if err != nil {
			return "", "", fmt.Errorf("failed to generate X25519 key pair: %w", err)
		}
		return identity.Recipient().String(), identity.String(), nil
	default:
		return "", "", fmt.Errorf("unsupported key type: %s", keyType)
	}
}

func encryptBatch(args []string) error {
	fs := flag.NewFlagSet("encrypt-batch", flag.ContinueOnError)
	filesJSON := fs.String("files-json", "", "path to file list json")
	outputDir := fs.String("output-dir", "", "base output directory")
	outputName := fs.String("output-name", "archive.tar.age", "output file name")
	compress := fs.Bool("compress", false, "write tar.gz before encryption")
	auth := fs.String("auth", "passphrase", "passphrase or publicKey")
	secretFile := fs.String("secret-file", "", "file containing passphrase or public key")
	duplicate := fs.String("duplicate", "rename", "rename or overwrite")
	concurrency := fs.Int("concurrency", 1, "maximum concurrent file operations")
	if err := fs.Parse(args); err != nil {
		return err
	}
	_ = clampConcurrency(*concurrency)

	files, err := loadFiles(*filesJSON)
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return errors.New("no input files")
	}
	secret, err := readSecret(*secretFile)
	if err != nil {
		return err
	}
	recipient, err := recipientFor(*auth, secret)
	if err != nil {
		return err
	}

	root, err := ensureSubdir(*outputDir, "encrypted")
	if err != nil {
		return err
	}
	outPath, err := outputPath(root, *outputName, *duplicate)
	if err != nil {
		return err
	}

	emit(event{Event: "progress", Phase: "Packing", Processed: 0, Total: len(files), Progress: 0.05})
	if err := encryptArchiveToFile(files, outPath, recipient, *compress, 0.05, 0.95); err != nil {
		return err
	}
	emit(event{Event: "file", Output: outPath})
	emit(event{Event: "done", Phase: "Complete", Progress: 1, Processed: 1, Total: 1, Success: 1, Outputs: []string{outPath}})
	return nil
}

func encryptSeparate(args []string) error {
	fs := flag.NewFlagSet("encrypt-separate", flag.ContinueOnError)
	filesJSON := fs.String("files-json", "", "path to file list json")
	outputDir := fs.String("output-dir", "", "base output directory")
	compress := fs.Bool("compress", false, "write tar.gz before encryption")
	auth := fs.String("auth", "passphrase", "passphrase or publicKey")
	secretFile := fs.String("secret-file", "", "file containing passphrase or public key")
	duplicate := fs.String("duplicate", "rename", "rename or overwrite")
	concurrency := fs.Int("concurrency", 1, "maximum concurrent file operations")
	if err := fs.Parse(args); err != nil {
		return err
	}

	files, err := loadFiles(*filesJSON)
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return errors.New("no input files")
	}
	secret, err := readSecret(*secretFile)
	if err != nil {
		return err
	}
	recipient, err := recipientFor(*auth, secret)
	if err != nil {
		return err
	}
	root, err := ensureSubdir(*outputDir, "encrypted")
	if err != nil {
		return err
	}

	results := runFileWorkers(files, clampConcurrency(*concurrency), func(index int, file fileSpec) operationResult {
		base := archiveEntryStem(file.Name)
		extension := ".tar.age"
		if *compress {
			extension = ".tar.gz.age"
		}
		outPath, err := safeOutputPath(root, base+extension, *duplicate)
		if err != nil {
			return operationResult{index: index, name: file.Name, err: err}
		}
		if err := encryptArchiveToFile([]fileSpec{file}, outPath, recipient, *compress, 0, 0); err != nil {
			return operationResult{index: index, name: file.Name, err: err}
		}
		return operationResult{index: index, name: file.Name, outputs: []string{outPath}}
	})
	outputs, success, failures, failureMessages := summarizeResults(results)

	emit(event{Event: "done", Phase: "Complete", Progress: 1, Processed: len(files), Total: len(files), Success: success, Fail: failures, Outputs: outputs})
	if success == 0 && failures > 0 {
		if len(failureMessages) > 0 {
			return fmt.Errorf("all files failed to encrypt: %s", strings.Join(failureMessages, "; "))
		}
		return errors.New("all files failed to encrypt")
	}
	return nil
}

func decryptFiles(args []string) error {
	fs := flag.NewFlagSet("decrypt", flag.ContinueOnError)
	filesJSON := fs.String("files-json", "", "path to file list json")
	outputDir := fs.String("output-dir", "", "base output directory")
	auth := fs.String("auth", "passphrase", "passphrase or privateKey")
	secretFile := fs.String("secret-file", "", "file containing passphrase or private key")
	duplicate := fs.String("duplicate", "rename", "rename or overwrite")
	concurrency := fs.Int("concurrency", 1, "maximum concurrent file operations")
	if err := fs.Parse(args); err != nil {
		return err
	}

	files, err := loadFiles(*filesJSON)
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return errors.New("no input files")
	}
	secret, err := readSecret(*secretFile)
	if err != nil {
		return err
	}
	identity, err := identityFor(*auth, secret)
	if err != nil {
		return err
	}
	root, err := ensureSubdir(*outputDir, "decrypted")
	if err != nil {
		return err
	}

	progress := newDecryptProgressTracker(files)
	progress.start()
	results := runFileWorkers(files, clampConcurrency(*concurrency), func(index int, file fileSpec) operationResult {
		written, err := decryptFileToOutputs(file.Path, root, file.Name, identity, *duplicate, progress)
		if err != nil {
			return operationResult{index: index, name: file.Name, err: err}
		}
		return operationResult{index: index, name: file.Name, outputs: written, outputsEmitted: true}
	})
	outputs, success, failures, failureMessages := summarizeResults(results)

	emit(event{Event: "done", Phase: "Complete", Progress: 1, Processed: len(files), Total: len(files), Success: success, Fail: failures, Outputs: outputs})
	if success == 0 && failures > 0 {
		if len(failureMessages) > 0 {
			return fmt.Errorf("all files failed to decrypt: %s", strings.Join(failureMessages, "; "))
		}
		return errors.New("all files failed to decrypt")
	}
	return nil
}

func loadFiles(path string) ([]fileSpec, error) {
	if path == "" {
		return nil, errors.New("missing --files-json")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var files []fileSpec
	if err := json.Unmarshal(data, &files); err != nil {
		return nil, err
	}
	for i := range files {
		files[i].Path = filepath.Clean(files[i].Path)
		if files[i].Name == "" {
			files[i].Name = filepath.Base(files[i].Path)
		}
	}
	return files, nil
}

func readSecret(path string) (string, error) {
	if path == "" {
		return "", errors.New("missing --secret-file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	secret := strings.TrimRight(string(data), "\r\n")
	if secret == "" {
		return "", errors.New("empty secret")
	}
	return secret, nil
}

func recipientFor(auth string, secret string) (age.Recipient, error) {
	switch auth {
	case "passphrase":
		return age.NewScryptRecipient(secret)
	case "publicKey":
		recipients, err := age.ParseRecipients(strings.NewReader(secret))
		if err != nil {
			return nil, err
		}
		if len(recipients) != 1 {
			return nil, fmt.Errorf("expected exactly one public key, got %d", len(recipients))
		}
		return recipients[0], nil
	default:
		return nil, fmt.Errorf("unsupported auth mode: %s", auth)
	}
}

func identityFor(auth string, secret string) (age.Identity, error) {
	switch auth {
	case "passphrase":
		return age.NewScryptIdentity(secret)
	case "privateKey":
		identities, err := age.ParseIdentities(strings.NewReader(secret))
		if err != nil {
			return nil, err
		}
		if len(identities) != 1 {
			return nil, fmt.Errorf("expected exactly one private key, got %d", len(identities))
		}
		return identities[0], nil
	default:
		return nil, fmt.Errorf("unsupported auth mode: %s", auth)
	}
}

func ensureSubdir(root string, name string) (string, error) {
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		root = filepath.Join(home, "Documents", "Age Mac Output")
	}
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	return dir, nil
}

func clampConcurrency(value int) int {
	if value < 1 {
		return 1
	}
	if value > maxConcurrency {
		return maxConcurrency
	}
	return value
}

func outputPath(dir string, name string, duplicate string) (string, error) {
	outputPathMu.Lock()
	defer outputPathMu.Unlock()
	return outputPathLocked(dir, name, duplicate)
}

func outputPathLocked(dir string, name string, duplicate string) (string, error) {
	if name == "" {
		return "", errors.New("empty output name")
	}
	cleanName := filepath.Base(name)
	path := filepath.Join(dir, cleanName)
	if duplicate == "overwrite" {
		if err := reserveOutputPath(path); err != nil {
			return "", err
		}
		return path, nil
	}
	ext := filepath.Ext(cleanName)
	base := strings.TrimSuffix(cleanName, ext)
	for i := 2; ; i++ {
		if outputCandidateAvailable(path) {
			if err := reserveOutputPath(path); err != nil {
				if errors.Is(err, os.ErrExist) {
					path = filepath.Join(dir, fmt.Sprintf("%s %d%s", base, i, ext))
					continue
				}
				return "", err
			}
			return path, nil
		}
		path = filepath.Join(dir, fmt.Sprintf("%s %d%s", base, i, ext))
	}
}

func outputCandidateAvailable(path string) bool {
	if _, err := os.Stat(path); err == nil || !errors.Is(err, os.ErrNotExist) {
		return false
	}
	if _, err := os.Stat(partialPath(path)); err == nil || !errors.Is(err, os.ErrNotExist) {
		return false
	}
	return true
}

func reserveOutputPath(path string) error {
	partial := partialPath(path)
	file, err := os.OpenFile(partial, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	return file.Close()
}

func partialPath(path string) string {
	return path + ".partial"
}

func createPartial(path string) (*os.File, string, error) {
	partial := partialPath(path)
	out, err := os.OpenFile(partial, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return nil, "", err
	}
	return out, partial, nil
}

func finishPartial(file *os.File, partial string, final string, errp *error) {
	if closeErr := file.Close(); *errp == nil && closeErr != nil {
		*errp = closeErr
	}
	if *errp != nil {
		_ = os.Remove(partial)
		return
	}
	if renameErr := os.Rename(partial, final); renameErr != nil {
		*errp = renameErr
		_ = os.Remove(partial)
	}
}

func encryptArchiveToFile(files []fileSpec, outputPath string, recipient age.Recipient, compress bool, start float64, end float64) (err error) {
	out, partial, err := createPartial(outputPath)
	if err != nil {
		return err
	}
	defer finishPartial(out, partial, outputPath, &err)

	ageWriter, err := age.Encrypt(out, recipient)
	if err != nil {
		return err
	}
	var ageClosed bool
	defer func() {
		if !ageClosed {
			_ = ageWriter.Close()
		}
	}()

	var tarTarget io.Writer = ageWriter
	var gz *gzip.Writer
	if compress {
		gz = gzip.NewWriter(ageWriter)
		tarTarget = gz
	}

	tw := tar.NewWriter(tarTarget)
	for index, file := range files {
		if err := addFileToTar(tw, file); err != nil {
			return err
		}
		if end > start && len(files) > 0 {
			progress := start + ((float64(index+1) / float64(len(files))) * (end - start))
			emit(event{Event: "progress", Phase: "Packing", Processed: index + 1, Total: len(files), Progress: progress})
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	if gz != nil {
		if err := gz.Close(); err != nil {
			return err
		}
	}
	if err := ageWriter.Close(); err != nil {
		return err
	}
	ageClosed = true
	return nil
}

func addFileToTar(tw *tar.Writer, file fileSpec) error {
	info, err := os.Stat(file.Path)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("directories are not supported as direct archive entries: %s", file.Path)
	}
	header, err := tar.FileInfoHeader(info, "")
	if err != nil {
		return err
	}
	header.Name = archiveEntryName(file.Name)
	if err := tw.WriteHeader(header); err != nil {
		return err
	}
	in, err := os.Open(file.Path)
	if err != nil {
		return err
	}
	defer in.Close()
	_, err = io.Copy(tw, in)
	return err
}

func archiveEntryName(name string) string {
	cleanPath := filepath.Clean(name)
	if filepath.IsAbs(cleanPath) || cleanPath == "." || strings.HasPrefix(cleanPath, ".."+string(filepath.Separator)) || cleanPath == ".." {
		return filepath.Base(name)
	}
	return filepath.ToSlash(cleanPath)
}

func archiveEntryStem(name string) string {
	entryName := archiveEntryName(name)
	extension := filepath.Ext(entryName)
	base := strings.TrimSuffix(entryName, extension)
	if base == "" {
		return entryName
	}
	return base
}

type operationResult struct {
	index          int
	name           string
	outputs        []string
	outputsEmitted bool
	err            error
}

func runFileWorkers(files []fileSpec, concurrency int, work func(index int, file fileSpec) operationResult) []operationResult {
	type job struct {
		index int
		file  fileSpec
	}

	jobs := make(chan job)
	results := make(chan operationResult, len(files))
	var wg sync.WaitGroup
	workers := concurrency
	if workers > len(files) {
		workers = len(files)
	}
	if workers < 1 {
		workers = 1
	}

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for job := range jobs {
				results <- work(job.index, job.file)
			}
		}()
	}

	go func() {
		for index, file := range files {
			jobs <- job{index: index, file: file}
		}
		close(jobs)
		wg.Wait()
		close(results)
	}()

	collected := make([]operationResult, 0, len(files))
	success := 0
	failures := 0
	for result := range results {
		collected = append(collected, result)
		if result.err != nil {
			failures++
		} else {
			success++
			if !result.outputsEmitted {
				for _, output := range result.outputs {
					emit(event{Event: "file", Output: output})
				}
			}
		}
		processed := success + failures
		emit(event{
			Event:     "progress",
			Phase:     fmt.Sprintf("Processed %s", result.name),
			Processed: processed,
			Total:     len(files),
			Success:   success,
			Fail:      failures,
			Progress:  float64(processed) / float64(len(files)),
		})
	}
	return collected
}

func summarizeResults(results []operationResult) ([]string, int, int, []string) {
	outputs := []string{}
	failureMessages := []string{}
	success := 0
	failures := 0
	for _, result := range results {
		if result.err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", result.name, result.err))
			continue
		}
		success++
		outputs = append(outputs, result.outputs...)
	}
	return outputs, success, failures, failureMessages
}

type decryptProgressTracker struct {
	mu           sync.Mutex
	totalBytes   int64
	written      int64
	totalFiles   int
	lastProgress float64
}

func newDecryptProgressTracker(files []fileSpec) *decryptProgressTracker {
	var totalBytes int64
	for _, file := range files {
		if info, err := os.Stat(file.Path); err == nil && info.Size() > 0 {
			totalBytes += info.Size()
		}
	}
	return &decryptProgressTracker{totalBytes: totalBytes, totalFiles: len(files)}
}

func (t *decryptProgressTracker) start() {
	emit(event{Event: "progress", Phase: "解密中", Processed: 0, Total: t.totalFiles, Progress: 0.01})
}

func (t *decryptProgressTracker) addWritten(n int64, label string) {
	if t == nil || n <= 0 {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	t.written += n
	if t.totalBytes <= 0 {
		return
	}
	progress := float64(t.written) / float64(t.totalBytes)
	if progress > 0.99 {
		progress = 0.99
	}
	if progress < 0.01 {
		progress = 0.01
	}
	if progress-t.lastProgress < 0.01 && progress < 0.99 {
		return
	}
	t.lastProgress = progress
	phase := "解密中"
	if label != "" {
		phase = "解密中 " + label
	}
	emit(event{Event: "progress", Phase: phase, Processed: 0, Total: t.totalFiles, Progress: progress})
}

func decryptFileToOutputs(inputPath string, outputDir string, originalName string, identity age.Identity, duplicate string, progress *decryptProgressTracker) ([]string, error) {
	in, err := os.Open(inputPath)
	if err != nil {
		return nil, err
	}
	defer in.Close()

	source, err := ageSource(in)
	if err != nil {
		return nil, err
	}
	decrypted, err := age.Decrypt(source, identity)
	if err != nil {
		return nil, classifyDecryptError(err)
	}
	buffered := newReplayableReader(decrypted)
	if outputs, err := extractTarMaybeGzipFromReader(buffered, outputDir, duplicate, progress); err == nil && len(outputs) > 0 {
		return outputs, nil
	} else if err != nil && !isNotArchiveError(err) {
		return nil, classifyDecryptError(err)
	}

	name := strings.TrimSuffix(originalName, ".age")
	if name == "" {
		name = "decrypted_output"
	}
	outPath, err := outputPath(outputDir, name, duplicate)
	if err != nil {
		return nil, err
	}
	if err := writeReaderToFile(buffered, outPath, func(n int64) {
		progress.addWritten(n, name)
	}); err != nil {
		return nil, classifyDecryptError(err)
	}
	emit(event{Event: "file", Output: outPath})
	return []string{outPath}, nil
}

func ageSource(in *os.File) (io.Reader, error) {
	header := make([]byte, len("-----BEGIN AGE ENCRYPTED FILE-----"))
	n, _ := io.ReadFull(in, header)
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	var source io.Reader = in
	if bytes.HasPrefix(header[:n], []byte("-----BEGIN AGE ENCRYPTED FILE-----")) {
		source = armor.NewReader(in)
	}
	return source, nil
}

var errNotArchive = errors.New("not tar archive")

type replayableReader struct {
	source    *bufio.Reader
	prefix    bytes.Buffer
	recording bool
	recorded  bytes.Buffer
}

func newReplayableReader(source io.Reader) *replayableReader {
	return &replayableReader{source: bufio.NewReader(source)}
}

func (r *replayableReader) Read(p []byte) (int, error) {
	if r.prefix.Len() > 0 {
		return r.prefix.Read(p)
	}
	n, err := r.source.Read(p)
	if r.recording && n > 0 {
		_, _ = r.recorded.Write(p[:n])
	}
	return n, err
}

func (r *replayableReader) Peek(n int) ([]byte, error) {
	if r.prefix.Len() > 0 {
		buffered := append([]byte(nil), r.prefix.Bytes()...)
		if len(buffered) >= n {
			return buffered[:n], nil
		}
		peeked, err := r.source.Peek(n - len(buffered))
		if err != nil {
			return nil, err
		}
		buffered = append(buffered, peeked...)
		return buffered, nil
	}
	return r.source.Peek(n)
}

func (r *replayableReader) startRecording() {
	r.recorded.Reset()
	r.recording = true
}

func (r *replayableReader) stopRecording() {
	r.recording = false
}

func (r *replayableReader) rewindRecorded() {
	r.recording = false
	if r.recorded.Len() == 0 {
		return
	}
	recorded := append([]byte(nil), r.recorded.Bytes()...)
	if r.prefix.Len() > 0 {
		recorded = append(recorded, r.prefix.Bytes()...)
	}
	r.prefix.Reset()
	_, _ = r.prefix.Write(recorded)
	r.recorded.Reset()
}

func extractTarMaybeGzipFromReader(source *replayableReader, outputDir string, duplicate string, progress *decryptProgressTracker) ([]string, error) {
	magic, err := source.Peek(2)
	if err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, bufio.ErrBufferFull) {
		return nil, err
	}
	var reader io.Reader = source
	var gz *gzip.Reader
	if len(magic) == 2 && magic[0] == 0x1f && magic[1] == 0x8b {
		source.startRecording()
		gz, err = gzip.NewReader(source)
		if err != nil {
			source.rewindRecorded()
			return nil, err
		}
		gzBuffer := bufio.NewReader(gz)
		header, err := gzBuffer.Peek(512)
		if err != nil {
			_ = gz.Close()
			source.rewindRecorded()
			if errors.Is(err, io.EOF) || errors.Is(err, bufio.ErrBufferFull) {
				return nil, errNotArchive
			}
			return nil, err
		}
		if !looksLikeTarHeader(header) {
			_ = gz.Close()
			source.rewindRecorded()
			return nil, errNotArchive
		}
		source.stopRecording()
		defer gz.Close()
		reader = gzBuffer
		return extractTarFromReader(reader, outputDir, duplicate, progress)
	}

	header, err := source.Peek(512)
	if err != nil {
		if errors.Is(err, io.EOF) || errors.Is(err, bufio.ErrBufferFull) {
			return nil, errNotArchive
		}
		return nil, err
	}
	if !looksLikeTarHeader(header) {
		return nil, errNotArchive
	}

	return extractTarFromReader(reader, outputDir, duplicate, progress)
}

func looksLikeTarHeader(header []byte) bool {
	if len(header) < 512 {
		return false
	}
	hasData := false
	for _, b := range header {
		if b != 0 {
			hasData = true
			break
		}
	}
	if !hasData {
		return false
	}

	rawChecksum := strings.Trim(string(header[148:156]), " \x00")
	if rawChecksum == "" {
		return false
	}
	expected, err := strconv.ParseInt(rawChecksum, 8, 64)
	if err != nil {
		return false
	}
	var actual int64
	for i, b := range header[:512] {
		if i >= 148 && i < 156 {
			actual += int64(' ')
			continue
		}
		actual += int64(b)
	}
	return actual == expected
}

func extractTarFromReader(reader io.Reader, outputDir string, duplicate string, progress *decryptProgressTracker) ([]string, error) {
	tr := tar.NewReader(reader)
	outputs := []string{}
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			if len(outputs) == 0 {
				return nil, errNotArchive
			}
			return nil, err
		}
		if header.FileInfo().IsDir() {
			continue
		}
		target, err := safeOutputPath(outputDir, header.Name, duplicate)
		if err != nil {
			return nil, err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return nil, err
		}
		label := filepath.Base(header.Name)
		if err := writeReaderToFile(tr, target, func(n int64) {
			progress.addWritten(n, label)
		}); err != nil {
			return nil, err
		}
		outputs = append(outputs, target)
		emit(event{Event: "file", Output: target})
	}
	if len(outputs) == 0 {
		return nil, errNotArchive
	}
	return outputs, nil
}

func isNotArchiveError(err error) bool {
	return errors.Is(err, errNotArchive)
}

func writeReaderToFile(reader io.Reader, path string, onWrite func(int64)) (err error) {
	out, partial, err := createPartial(path)
	if err != nil {
		return err
	}
	defer finishPartial(out, partial, path, &err)
	target := io.Writer(out)
	if onWrite != nil {
		target = progressWriter{writer: out, onWrite: onWrite}
	}
	_, err = io.Copy(target, reader)
	return err
}

type progressWriter struct {
	writer  io.Writer
	onWrite func(int64)
}

func (w progressWriter) Write(p []byte) (int, error) {
	n, err := w.writer.Write(p)
	if n > 0 {
		w.onWrite(int64(n))
	}
	return n, err
}

func classifyDecryptError(err error) error {
	if err == nil {
		return nil
	}
	message := err.Error()
	switch {
	case errors.Is(err, io.ErrUnexpectedEOF),
		strings.Contains(message, "failed to decrypt and authenticate payload chunk"),
		strings.Contains(message, "trailing data after end of encrypted file"),
		strings.Contains(message, "unexpected EOF"):
		return fmt.Errorf("encrypted file is incomplete or corrupted: %w", err)
	default:
		return err
	}
}

func safeOutputPath(root string, archiveName string, duplicate string) (string, error) {
	outputPathMu.Lock()
	defer outputPathMu.Unlock()
	return safeOutputPathLocked(root, archiveName, duplicate)
}

func safeOutputPathLocked(root string, archiveName string, duplicate string) (string, error) {
	clean := filepath.Clean(archiveName)
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, ".."+string(filepath.Separator)) || clean == ".." {
		return "", fmt.Errorf("unsafe archive path: %s", archiveName)
	}
	full := filepath.Join(root, clean)
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		return "", err
	}
	if duplicate == "overwrite" {
		if err := reserveOutputPath(full); err != nil {
			return "", err
		}
		return full, nil
	}
	dir := filepath.Dir(full)
	base := filepath.Base(full)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	candidate := full
	for i := 2; ; i++ {
		if outputCandidateAvailable(candidate) {
			if err := reserveOutputPath(candidate); err != nil {
				if errors.Is(err, os.ErrExist) {
					candidate = filepath.Join(dir, fmt.Sprintf("%s %d%s", stem, i, ext))
					continue
				}
				return "", err
			}
			return candidate, nil
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s %d%s", stem, i, ext))
	}
}
