package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"filippo.io/age"
	"filippo.io/age/armor"
)

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
		err = keygen()
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
	fmt.Println(string(data))
}

func keygen() error {
	identity, err := age.GenerateX25519Identity()
	if err != nil {
		return fmt.Errorf("failed to generate key pair: %w", err)
	}
	payload := map[string]string{
		"event":      "keypair",
		"publicKey":  identity.Recipient().String(),
		"privateKey": identity.String(),
	}
	data, _ := json.Marshal(payload)
	fmt.Println(string(data))
	return nil
}

func encryptBatch(args []string) error {
	fs := flag.NewFlagSet("encrypt-batch", flag.ContinueOnError)
	filesJSON := fs.String("files-json", "", "path to file list json")
	outputDir := fs.String("output-dir", "", "base output directory")
	outputName := fs.String("output-name", "archive.tar.gz.age", "output file name")
	compress := fs.Bool("compress", true, "write tar.gz before encryption")
	auth := fs.String("auth", "passphrase", "passphrase or publicKey")
	secretFile := fs.String("secret-file", "", "file containing passphrase or public key")
	duplicate := fs.String("duplicate", "rename", "rename or overwrite")
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
	outPath, err := outputPath(root, *outputName, *duplicate)
	if err != nil {
		return err
	}

	tempDir, err := os.MkdirTemp("", "age-mac-batch-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	archivePath := filepath.Join(tempDir, "payload.tar")
	if *compress {
		archivePath += ".gz"
	}

	emit(event{Event: "progress", Phase: "Packing", Processed: 0, Total: len(files), Progress: 0.05})
	if err := writeArchive(files, archivePath, *compress, 0.05, 0.45); err != nil {
		return err
	}
	emit(event{Event: "progress", Phase: "Encrypting", Processed: len(files), Total: len(files), Progress: 0.55})
	if err := encryptFile(archivePath, outPath, recipient); err != nil {
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
	compress := fs.Bool("compress", true, "write tar.gz before encryption")
	auth := fs.String("auth", "passphrase", "passphrase or publicKey")
	secretFile := fs.String("secret-file", "", "file containing passphrase or public key")
	duplicate := fs.String("duplicate", "rename", "rename or overwrite")
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

	tempDir, err := os.MkdirTemp("", "age-mac-separate-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	outputs := make([]string, 0, len(files))
	success := 0
	failures := 0
	failureMessages := []string{}
	for index, file := range files {
		phase := fmt.Sprintf("Encrypting %s", file.Name)
		emit(event{Event: "progress", Phase: phase, Processed: index, Total: len(files), Success: success, Fail: failures, Progress: float64(index) / float64(len(files))})

		archivePath := filepath.Join(tempDir, fmt.Sprintf("payload-%d.tar", index))
		if *compress {
			archivePath += ".gz"
		}
		if err := writeArchive([]fileSpec{file}, archivePath, *compress, 0, 0); err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", file.Name, err))
			continue
		}
		base := strings.TrimSuffix(file.Name, filepath.Ext(file.Name))
		if base == "" {
			base = file.Name
		}
		extension := ".tar.age"
		if *compress {
			extension = ".tar.gz.age"
		}
		outPath, err := outputPath(root, base+extension, *duplicate)
		if err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", file.Name, err))
			continue
		}
		if err := encryptFile(archivePath, outPath, recipient); err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", file.Name, err))
			continue
		}
		success++
		outputs = append(outputs, outPath)
		emit(event{Event: "file", Output: outPath})
	}

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

	tempDir, err := os.MkdirTemp("", "age-mac-decrypt-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	outputs := []string{}
	success := 0
	failures := 0
	failureMessages := []string{}
	for index, file := range files {
		emit(event{Event: "progress", Phase: "Decrypting " + file.Name, Processed: index, Total: len(files), Success: success, Fail: failures, Progress: float64(index) / float64(len(files))})
		decryptedPath := filepath.Join(tempDir, fmt.Sprintf("decrypted-%d.bin", index))
		if err := decryptFile(file.Path, decryptedPath, identity); err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", file.Name, err))
			continue
		}
		written, err := unpackOrWrite(decryptedPath, root, file.Name, *duplicate)
		if err != nil {
			failures++
			failureMessages = append(failureMessages, fmt.Sprintf("%s: %v", file.Name, err))
			continue
		}
		success++
		outputs = append(outputs, written...)
		for _, out := range written {
			emit(event{Event: "file", Output: out})
		}
	}

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
		return age.ParseX25519Recipient(secret)
	default:
		return nil, fmt.Errorf("unsupported auth mode: %s", auth)
	}
}

func identityFor(auth string, secret string) (age.Identity, error) {
	switch auth {
	case "passphrase":
		return age.NewScryptIdentity(secret)
	case "privateKey":
		return age.ParseX25519Identity(secret)
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

func outputPath(dir string, name string, duplicate string) (string, error) {
	if name == "" {
		return "", errors.New("empty output name")
	}
	cleanName := filepath.Base(name)
	path := filepath.Join(dir, cleanName)
	if duplicate == "overwrite" {
		return path, nil
	}
	ext := filepath.Ext(cleanName)
	base := strings.TrimSuffix(cleanName, ext)
	for i := 2; ; i++ {
		if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
			return path, nil
		}
		path = filepath.Join(dir, fmt.Sprintf("%s %d%s", base, i, ext))
	}
}

func writeArchive(files []fileSpec, outputPath string, compress bool, start float64, end float64) error {
	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	var tarTarget io.Writer = out
	var gz *gzip.Writer
	if compress {
		gz = gzip.NewWriter(out)
		defer gz.Close()
		tarTarget = gz
	}

	tw := tar.NewWriter(tarTarget)
	defer tw.Close()

	for index, file := range files {
		if err := addFileToTar(tw, file); err != nil {
			return err
		}
		if end > start && len(files) > 0 {
			progress := start + ((float64(index+1) / float64(len(files))) * (end - start))
			emit(event{Event: "progress", Phase: "Packing", Processed: index + 1, Total: len(files), Progress: progress})
		}
	}
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
	header.Name = filepath.Base(file.Name)
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

func encryptFile(inputPath string, outputPath string, recipient age.Recipient) error {
	in, err := os.Open(inputPath)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	w, err := age.Encrypt(out, recipient)
	if err != nil {
		return err
	}
	if _, err := io.Copy(w, in); err != nil {
		_ = w.Close()
		return err
	}
	return w.Close()
}

func decryptFile(inputPath string, outputPath string, identity age.Identity) error {
	in, err := os.Open(inputPath)
	if err != nil {
		return err
	}
	defer in.Close()

	header := make([]byte, len("-----BEGIN AGE ENCRYPTED FILE-----"))
	n, _ := io.ReadFull(in, header)
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return err
	}

	var source io.Reader = in
	if bytes.HasPrefix(header[:n], []byte("-----BEGIN AGE ENCRYPTED FILE-----")) {
		source = armor.NewReader(in)
	}

	r, err := age.Decrypt(source, identity)
	if err != nil {
		return err
	}

	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, r)
	return err
}

func unpackOrWrite(inputPath string, outputDir string, originalName string, duplicate string) ([]string, error) {
	if outputs, err := extractTarMaybeGzip(inputPath, outputDir, duplicate); err == nil && len(outputs) > 0 {
		return outputs, nil
	}

	name := strings.TrimSuffix(originalName, ".age")
	if name == "" {
		name = "decrypted_output"
	}
	outPath, err := outputPath(outputDir, name, duplicate)
	if err != nil {
		return nil, err
	}
	in, err := os.Open(inputPath)
	if err != nil {
		return nil, err
	}
	defer in.Close()
	out, err := os.Create(outPath)
	if err != nil {
		return nil, err
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		return nil, err
	}
	return []string{outPath}, nil
}

func extractTarMaybeGzip(inputPath string, outputDir string, duplicate string) ([]string, error) {
	in, err := os.Open(inputPath)
	if err != nil {
		return nil, err
	}
	defer in.Close()

	var source io.Reader = in
	magic := make([]byte, 2)
	n, _ := io.ReadFull(in, magic)
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	if n == 2 && magic[0] == 0x1f && magic[1] == 0x8b {
		gz, err := gzip.NewReader(in)
		if err != nil {
			return nil, err
		}
		defer gz.Close()
		source = gz
	}

	tr := tar.NewReader(source)
	outputs := []string{}
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
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
		out, err := os.Create(target)
		if err != nil {
			return nil, err
		}
		if _, err := io.Copy(out, tr); err != nil {
			_ = out.Close()
			return nil, err
		}
		if err := out.Close(); err != nil {
			return nil, err
		}
		outputs = append(outputs, target)
	}
	if len(outputs) == 0 {
		return nil, errors.New("archive had no files")
	}
	return outputs, nil
}

func safeOutputPath(root string, archiveName string, duplicate string) (string, error) {
	clean := filepath.Clean(archiveName)
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, ".."+string(filepath.Separator)) || clean == ".." {
		return "", fmt.Errorf("unsafe archive path: %s", archiveName)
	}
	full := filepath.Join(root, clean)
	if duplicate == "overwrite" {
		return full, nil
	}
	dir := filepath.Dir(full)
	base := filepath.Base(full)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	candidate := full
	for i := 2; ; i++ {
		if _, err := os.Stat(candidate); errors.Is(err, os.ErrNotExist) {
			return candidate, nil
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s %d%s", stem, i, ext))
	}
}
