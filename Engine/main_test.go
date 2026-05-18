/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
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
