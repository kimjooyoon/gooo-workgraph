package inventory

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestObserveClosedWorkspace(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, root, "cmd/app.go", "package main\n\n")
	mustWrite(t, root, "spec/main.gooo", "package spec\nnamespace sample\n")
	mustWrite(t, root, "README.md", "fixture\n")
	mustWrite(t, root, "notes.txt", "note")

	report := Observe(root)
	if report.Decision != "WORKSPACE_INVENTORY_OBSERVED" || report.Claim.State != "CLOSED" {
		t.Fatalf("unexpected decision: %#v", report.Claim)
	}
	if report.Summary.Directories != 2 || report.Summary.Files != 4 {
		t.Fatalf("unexpected structure totals: %#v", report.Summary)
	}
	if report.Summary.GoFiles != 1 || report.Summary.GoLines != 2 {
		t.Fatalf("unexpected Go totals: %#v", report.Summary)
	}
	if report.Summary.GoooFiles != 1 || report.Summary.GoooLines != 2 {
		t.Fatalf("unexpected Gooo totals: %#v", report.Summary)
	}
	if !report.Summary.RootReadmePresent || report.Summary.RootReadmeRequired || !report.Summary.RootReadmeExcluded {
		t.Fatalf("root README policy changed: %#v", report.Summary)
	}

	paths := make([]string, 0, len(report.Files))
	for _, file := range report.Files {
		paths = append(paths, file.Path)
	}
	want := []string{"README.md", "cmd/app.go", "notes.txt", "spec/main.gooo"}
	if !slices.Equal(paths, want) {
		t.Fatalf("paths are not deterministic: got %v want %v", paths, want)
	}
}

func TestObserveMissingWorkspaceIsUnknown(t *testing.T) {
	report := Observe(filepath.Join(t.TempDir(), "missing"))
	if report.Decision != "WORKSPACE_INVENTORY_UNKNOWN" || report.Claim.State != "UNKNOWN" {
		t.Fatalf("missing root was not UNKNOWN: %#v", report.Claim)
	}
	if report.Claim.UnknownClass == nil || *report.Claim.UnknownClass != "DIRECT_MISSING" {
		t.Fatalf("missing root lost its unknown class: %#v", report.Claim)
	}
	if report.Claim.NextOperation != "PROVIDE_WORKSPACE_ROOT" {
		t.Fatalf("missing root lost its next operation: %#v", report.Claim)
	}
}

func TestObserveFileRootIsRefuted(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "not-a-directory")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}

	report := Observe(file)
	if report.Decision != "FAIL_CLOSED" || report.Claim.State != "REFUTED" {
		t.Fatalf("file root was not REFUTED: %#v", report.Claim)
	}
	if report.Claim.Reason != "WORKSPACE_ROOT_NOT_DIRECTORY" || report.Claim.UnknownClass != nil {
		t.Fatalf("file root has the wrong refutation: %#v", report.Claim)
	}
}

func mustWrite(t *testing.T, root, relative, content string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(relative))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
