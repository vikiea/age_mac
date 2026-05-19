/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"filippo.io/age"
)

func TestEncryptSeparateSupportsCompression(t *testing.T) {
	tempDir := t.TempDir()
	inputDir := filepath.Join(tempDir, "input")
	outputDir := filepath.Join(tempDir, "output")
	if err := os.MkdirAll(inputDir, 0755); err != nil {
		t.Fatal(err)
	}
	inputPath := filepath.Join(inputDir, "note.txt")
	if err := os.WriteFile(inputPath, []byte("hello compressed separate mode\n"), 0644); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: inputPath, Name: "note.txt"}})
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	err := encryptSeparate([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
		"--compress=true",
	})
	if err != nil {
		t.Fatalf("encryptSeparate returned error: %v", err)
	}

	encryptedPath := filepath.Join(outputDir, "encrypted", "note.tar.gz.age")
	if _, err := os.Stat(encryptedPath); err != nil {
		t.Fatalf("expected compressed separate output %s: %v", encryptedPath, err)
	}

	encryptedFilesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "note.tar.gz.age"}})
	if err := decryptFiles([]string{
		"--files-json", encryptedFilesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", "note.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(decrypted) != "hello compressed separate mode\n" {
		t.Fatalf("decrypted content mismatch: %q", string(decrypted))
	}
}

func TestEncryptDefaultsDisableCompression(t *testing.T) {
	tempDir := t.TempDir()
	inputDir := filepath.Join(tempDir, "input")
	outputDir := filepath.Join(tempDir, "output")
	if err := os.MkdirAll(inputDir, 0755); err != nil {
		t.Fatal(err)
	}
	inputPath := filepath.Join(inputDir, "note.txt")
	if err := os.WriteFile(inputPath, []byte("hello default no compression\n"), 0644); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: inputPath, Name: "note.txt"}})
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	if err := encryptBatch([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("encryptBatch returned error: %v", err)
	}
	if _, err := os.Stat(filepath.Join(outputDir, "encrypted", "archive.tar.age")); err != nil {
		t.Fatalf("expected default batch output to be archive.tar.age: %v", err)
	}
	if _, err := os.Stat(filepath.Join(outputDir, "encrypted", "archive.tar.gz.age")); !os.IsNotExist(err) {
		t.Fatalf("default batch output should not be archive.tar.gz.age, stat err=%v", err)
	}

	if err := encryptSeparate([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("encryptSeparate returned error: %v", err)
	}
	if _, err := os.Stat(filepath.Join(outputDir, "encrypted", "note.tar.age")); err != nil {
		t.Fatalf("expected default separate output to be note.tar.age: %v", err)
	}
}

func TestEncryptBatchKeyPairRoundTrip(t *testing.T) {
	tempDir := t.TempDir()
	inputDir := filepath.Join(tempDir, "input")
	outputDir := filepath.Join(tempDir, "output")
	if err := os.MkdirAll(inputDir, 0755); err != nil {
		t.Fatal(err)
	}
	inputPath := filepath.Join(inputDir, "note.txt")
	if err := os.WriteFile(inputPath, []byte("hello key pair mode\n"), 0644); err != nil {
		t.Fatal(err)
	}

	identity, err := age.GenerateX25519Identity()
	if err != nil {
		t.Fatal(err)
	}
	publicFile := filepath.Join(tempDir, "public.txt")
	privateFile := filepath.Join(tempDir, "private.txt")
	if err := os.WriteFile(publicFile, []byte(identity.Recipient().String()), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(privateFile, []byte(identity.String()), 0600); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: inputPath, Name: "note.txt"}})
	if err := encryptBatch([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--output-name", "key-roundtrip.tar.gz.age",
		"--auth", "publicKey",
		"--secret-file", publicFile,
		"--duplicate", "overwrite",
		"--compress=true",
	}); err != nil {
		t.Fatalf("encryptBatch returned error: %v", err)
	}

	encryptedPath := filepath.Join(outputDir, "encrypted", "key-roundtrip.tar.gz.age")
	encryptedFilesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "key-roundtrip.tar.gz.age"}})
	if err := decryptFiles([]string{
		"--files-json", encryptedFilesJSON,
		"--output-dir", outputDir,
		"--auth", "privateKey",
		"--secret-file", privateFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", "note.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(decrypted) != "hello key pair mode\n" {
		t.Fatalf("decrypted content mismatch: %q", string(decrypted))
	}
}

func TestSeparateEncryptAndDecryptHonorConcurrency(t *testing.T) {
	tempDir := t.TempDir()
	inputDir := filepath.Join(tempDir, "input")
	outputDir := filepath.Join(tempDir, "output")
	if err := os.MkdirAll(inputDir, 0755); err != nil {
		t.Fatal(err)
	}

	files := make([]fileSpec, 0, 3)
	for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
		path := filepath.Join(inputDir, name)
		if err := os.WriteFile(path, []byte("content for "+name+"\n"), 0644); err != nil {
			t.Fatal(err)
		}
		files = append(files, fileSpec{Path: path, Name: name})
	}

	filesJSON := writeTestFilesJSON(t, tempDir, files)
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	if err := encryptSeparate([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "rename",
		"--compress=true",
		"--concurrency", "2",
	}); err != nil {
		t.Fatalf("encryptSeparate returned error: %v", err)
	}

	encrypted := []fileSpec{
		{Path: filepath.Join(outputDir, "encrypted", "a.tar.gz.age"), Name: "a.tar.gz.age"},
		{Path: filepath.Join(outputDir, "encrypted", "b.tar.gz.age"), Name: "b.tar.gz.age"},
		{Path: filepath.Join(outputDir, "encrypted", "c.tar.gz.age"), Name: "c.tar.gz.age"},
	}
	encryptedFilesJSON := writeTestFilesJSON(t, tempDir, encrypted)
	if err := decryptFiles([]string{
		"--files-json", encryptedFilesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
		"--concurrency", "2",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	for _, file := range files {
		decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", file.Name))
		if err != nil {
			t.Fatal(err)
		}
		expected := "content for " + file.Name + "\n"
		if string(decrypted) != expected {
			t.Fatalf("%s decrypted content mismatch: %q", file.Name, string(decrypted))
		}
	}
}

func TestDecryptBatchEmitsStreamingProgress(t *testing.T) {
	tempDir := t.TempDir()
	inputDir := filepath.Join(tempDir, "input")
	outputDir := filepath.Join(tempDir, "output")
	if err := os.MkdirAll(inputDir, 0755); err != nil {
		t.Fatal(err)
	}

	files := make([]fileSpec, 0, 3)
	for _, name := range []string{"alpha.bin", "beta.bin", "gamma.bin"} {
		path := filepath.Join(inputDir, name)
		if err := os.WriteFile(path, bytes.Repeat([]byte(name), 4096), 0644); err != nil {
			t.Fatal(err)
		}
		files = append(files, fileSpec{Path: path, Name: name})
	}

	filesJSON := writeTestFilesJSON(t, tempDir, files)
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	if err := encryptBatch([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--output-name", "streaming-progress.tar.age",
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
		"--compress=false",
	}); err != nil {
		t.Fatalf("encryptBatch returned error: %v", err)
	}

	encryptedPath := filepath.Join(outputDir, "encrypted", "streaming-progress.tar.age")
	encryptedFilesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "streaming-progress.tar.age"}})
	events := captureEngineEvents(t, func() error {
		return decryptFiles([]string{
			"--files-json", encryptedFilesJSON,
			"--output-dir", outputDir,
			"--auth", "passphrase",
			"--secret-file", secretFile,
			"--duplicate", "overwrite",
		})
	})

	sawStreamingProgress := false
	fileEvents := 0
	for _, event := range events {
		if event.Event == "progress" && event.Progress > 0 && event.Progress < 1 {
			sawStreamingProgress = true
		}
		if event.Event == "file" {
			fileEvents++
		}
	}
	if !sawStreamingProgress {
		t.Fatalf("expected streaming progress before completion, got events: %#v", events)
	}
	if fileEvents != len(files) {
		t.Fatalf("expected %d file events, got %d: %#v", len(files), fileEvents, events)
	}
}

func TestDecryptPlainAgeFilePreservesContent(t *testing.T) {
	tempDir := t.TempDir()
	outputDir := filepath.Join(tempDir, "output")
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	encryptedPath := filepath.Join(tempDir, "plain.txt.age")
	out, err := os.Create(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := age.NewScryptRecipient("test-passphrase")
	if err != nil {
		t.Fatal(err)
	}
	writer, err := age.Encrypt(out, recipient)
	if err != nil {
		t.Fatal(err)
	}
	payload := "plain age payload that is not a tar archive\n"
	if _, err := writer.Write([]byte(payload)); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := out.Close(); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "plain.txt.age"}})
	if err := decryptFiles([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", "plain.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(decrypted) != payload {
		t.Fatalf("plain decrypted content mismatch: %q", string(decrypted))
	}
}

func TestDecryptPlainGzipAgeFilePreservesContent(t *testing.T) {
	tempDir := t.TempDir()
	outputDir := filepath.Join(tempDir, "output")
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	var compressed bytes.Buffer
	gzipWriter := gzip.NewWriter(&compressed)
	if _, err := gzipWriter.Write([]byte("gzip payload that is not a tar archive\n")); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}

	encryptedPath := filepath.Join(tempDir, "plain.gz.age")
	out, err := os.Create(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := age.NewScryptRecipient("test-passphrase")
	if err != nil {
		t.Fatal(err)
	}
	writer, err := age.Encrypt(out, recipient)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := writer.Write(compressed.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := out.Close(); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "plain.gz.age"}})
	if err := decryptFiles([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", "plain.gz"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(decrypted, compressed.Bytes()) {
		t.Fatalf("plain gzip decrypted content mismatch: got %d bytes, want %d", len(decrypted), compressed.Len())
	}
}

func TestDecryptTruncatedFileReportsCorruption(t *testing.T) {
	tempDir := t.TempDir()
	outputDir := filepath.Join(tempDir, "output")
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	encryptedPath := filepath.Join(tempDir, "truncated.tar.age")
	out, err := os.Create(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := age.NewScryptRecipient("test-passphrase")
	if err != nil {
		t.Fatal(err)
	}
	writer, err := age.Encrypt(out, recipient)
	if err != nil {
		t.Fatal(err)
	}
	tarWriter := tar.NewWriter(writer)
	payload := []byte("payload that will be truncated\n")
	if err := tarWriter.WriteHeader(&tar.Header{
		Name: "truncated.txt",
		Mode: 0644,
		Size: int64(len(payload)),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := tarWriter.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := out.Close(); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(data) < 8 {
		t.Fatalf("encrypted test file unexpectedly short: %d", len(data))
	}
	if err := os.WriteFile(encryptedPath, data[:len(data)-4], 0600); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "truncated.tar.age"}})
	err = decryptFiles([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	})
	if err == nil {
		t.Fatal("decryptFiles returned nil for truncated file")
	}
	if !strings.Contains(err.Error(), "encrypted file is incomplete or corrupted") {
		t.Fatalf("expected corruption error, got: %v", err)
	}
	if matches, err := filepath.Glob(filepath.Join(outputDir, "decrypted", "*.partial")); err != nil {
		t.Fatal(err)
	} else if len(matches) != 0 {
		t.Fatalf("partial files should be cleaned up after failure: %v", matches)
	}
}

func TestDecryptArchiveWithNestedPathCreatesPartialParent(t *testing.T) {
	tempDir := t.TempDir()
	outputDir := filepath.Join(tempDir, "output")
	secretFile := filepath.Join(tempDir, "secret.txt")
	if err := os.WriteFile(secretFile, []byte("test-passphrase"), 0600); err != nil {
		t.Fatal(err)
	}

	encryptedPath := filepath.Join(tempDir, "nested.tar.age")
	out, err := os.Create(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := age.NewScryptRecipient("test-passphrase")
	if err != nil {
		t.Fatal(err)
	}
	writer, err := age.Encrypt(out, recipient)
	if err != nil {
		t.Fatal(err)
	}
	tarWriter := tar.NewWriter(writer)
	payload := []byte("nested archive payload\n")
	if err := tarWriter.WriteHeader(&tar.Header{
		Name: "nested/note.txt",
		Mode: 0644,
		Size: int64(len(payload)),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := tarWriter.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := out.Close(); err != nil {
		t.Fatal(err)
	}

	filesJSON := writeTestFilesJSON(t, tempDir, []fileSpec{{Path: encryptedPath, Name: "nested.tar.age"}})
	if err := decryptFiles([]string{
		"--files-json", filesJSON,
		"--output-dir", outputDir,
		"--auth", "passphrase",
		"--secret-file", secretFile,
		"--duplicate", "overwrite",
	}); err != nil {
		t.Fatalf("decryptFiles returned error: %v", err)
	}

	decrypted, err := os.ReadFile(filepath.Join(outputDir, "decrypted", "nested", "note.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(decrypted) != string(payload) {
		t.Fatalf("nested decrypted content mismatch: %q", string(decrypted))
	}
}

func writeTestFilesJSON(t *testing.T, dir string, files []fileSpec) string {
	t.Helper()
	data, err := json.Marshal(files)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "files-"+filepath.Base(files[0].Name)+".json")
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatal(err)
	}
	return path
}

func captureEngineEvents(t *testing.T, run func() error) []event {
	t.Helper()
	originalStdout := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = writer

	runErr := run()
	if closeErr := writer.Close(); closeErr != nil {
		t.Fatal(closeErr)
	}
	os.Stdout = originalStdout
	if runErr != nil {
		t.Fatalf("engine command returned error: %v", runErr)
	}

	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	events := make([]event, 0, len(lines))
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var decoded event
		if err := json.Unmarshal([]byte(line), &decoded); err != nil {
			t.Fatalf("invalid event line %q: %v", line, err)
		}
		events = append(events, decoded)
	}
	return events
}
