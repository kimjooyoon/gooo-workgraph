package inventory

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const Schema = "gooo/workgraph-workspace-inventory/v1"

var errSymbolicLink = errors.New("symbolic link crosses the observation boundary")

type Subject struct {
	Root     string `json:"root"`
	RootKind string `json:"root_kind"`
}

type Summary struct {
	Directories        int  `json:"directories"`
	Files              int  `json:"files"`
	GoFiles            int  `json:"go_files"`
	GoooFiles          int  `json:"gooo_files"`
	OtherFiles         int  `json:"other_files"`
	GoLines            int  `json:"go_lines"`
	GoooLines          int  `json:"gooo_lines"`
	OtherLines         int  `json:"other_lines"`
	TotalLines         int  `json:"total_lines"`
	RootReadmePresent  bool `json:"root_readme_present"`
	RootReadmeRequired bool `json:"root_readme_required"`
	RootReadmeExcluded bool `json:"root_readme_excluded"`
}

type FileObservation struct {
	Path     string `json:"path"`
	Language string `json:"language"`
	Lines    int    `json:"lines"`
	Bytes    int64  `json:"bytes"`
}

type Claim struct {
	State         string   `json:"state"`
	Stage         *string  `json:"stage"`
	Step          *string  `json:"step"`
	Reason        string   `json:"reason"`
	UnknownClass  *string  `json:"unknown_class"`
	NextOperation string   `json:"next_operation"`
	BlockedBy     []string `json:"blocked_by"`
}

type Authority struct {
	Source              string `json:"source"`
	ObservationMode     string `json:"observation_mode"`
	RepositoryWrites    int    `json:"repository_writes"`
	RootReadmeReadiness string `json:"root_readme_readiness"`
}

type Report struct {
	Schema    string            `json:"schema"`
	Decision  string            `json:"decision"`
	Subject   Subject           `json:"subject"`
	Summary   Summary           `json:"summary"`
	Files     []FileObservation `json:"files"`
	Claim     Claim             `json:"claim"`
	Authority Authority         `json:"authority"`
}

func Observe(rootArgument string) Report {
	root := filepath.Clean(rootArgument)
	report := newReport(filepath.ToSlash(root))

	info, err := os.Lstat(root)
	if errors.Is(err, fs.ErrNotExist) {
		report.Subject.RootKind = "MISSING"
		return unknown(report)
	}
	if err != nil {
		report.Subject.RootKind = "UNREADABLE"
		return refuted(report, "INPUT", "OBSERVE_WORKSPACE_ROOT", "WORKSPACE_ROOT_STAT_FAILED", "REPAIR_WORKSPACE_ACCESS")
	}
	if info.Mode()&os.ModeSymlink != 0 {
		report.Subject.RootKind = "SYMLINK"
		return refuted(report, "INPUT", "VALIDATE_WORKSPACE_ROOT", "WORKSPACE_ROOT_SYMBOLIC_LINK", "SELECT_WORKSPACE_DIRECTORY")
	}
	if !info.IsDir() {
		report.Subject.RootKind = "FILE"
		return refuted(report, "INPUT", "VALIDATE_WORKSPACE_ROOT", "WORKSPACE_ROOT_NOT_DIRECTORY", "SELECT_WORKSPACE_DIRECTORY")
	}
	report.Subject.RootKind = "DIRECTORY"

	walkErr := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == root {
			return nil
		}

		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("%w: %s", errSymbolicLink, relative)
		}
		if entry.IsDir() {
			report.Summary.Directories++
			return nil
		}

		fileInfo, err := entry.Info()
		if err != nil {
			return err
		}
		if !fileInfo.Mode().IsRegular() {
			return nil
		}

		lines, err := countLines(path)
		if err != nil {
			return err
		}
		language := languageFor(relative)
		report.Files = append(report.Files, FileObservation{
			Path:     relative,
			Language: language,
			Lines:    lines,
			Bytes:    fileInfo.Size(),
		})
		report.Summary.Files++
		report.Summary.TotalLines += lines

		switch language {
		case "GO":
			report.Summary.GoFiles++
			report.Summary.GoLines += lines
		case "GOOO":
			report.Summary.GoooFiles++
			report.Summary.GoooLines += lines
		default:
			report.Summary.OtherFiles++
			report.Summary.OtherLines += lines
		}
		if !strings.Contains(relative, "/") && strings.EqualFold(relative, "README.md") {
			report.Summary.RootReadmePresent = true
		}
		return nil
	})
	if walkErr != nil {
		if errors.Is(walkErr, errSymbolicLink) {
			return refuted(report, "OBSERVER", "WALK_WORKSPACE_TREE", "WORKSPACE_SYMBOLIC_LINK_REFUTED", "REMOVE_OR_DECLARE_SYMBOLIC_LINK")
		}
		return refuted(report, "OBSERVER", "WALK_WORKSPACE_TREE", "WORKSPACE_TRAVERSAL_FAILED", "REPAIR_WORKSPACE_ACCESS")
	}

	sort.Slice(report.Files, func(i, j int) bool {
		return report.Files[i].Path < report.Files[j].Path
	})
	report.Decision = "WORKSPACE_INVENTORY_OBSERVED"
	report.Claim = Claim{
		State:         "CLOSED",
		Reason:        "WORKSPACE_INVENTORY_OBSERVED",
		NextOperation: "NONE",
		BlockedBy:     []string{},
	}
	return report
}

func newReport(root string) Report {
	return Report{
		Schema:   Schema,
		Decision: "WORKSPACE_INVENTORY_UNKNOWN",
		Subject: Subject{
			Root:     root,
			RootKind: "UNKNOWN",
		},
		Summary: Summary{
			RootReadmeRequired: false,
			RootReadmeExcluded: true,
		},
		Files: []FileObservation{},
		Authority: Authority{
			Source:              "examples/workspace-inventory/main.gooo",
			ObservationMode:     "READ_ONLY",
			RepositoryWrites:    0,
			RootReadmeReadiness: "EXCLUDED",
		},
	}
}

func unknown(report Report) Report {
	report.Decision = "WORKSPACE_INVENTORY_UNKNOWN"
	report.Claim = Claim{
		State:         "UNKNOWN",
		Stage:         new("INPUT"),
		Step:          new("OBSERVE_WORKSPACE_ROOT"),
		Reason:        "WORKSPACE_ROOT_NOT_FOUND",
		UnknownClass:  new("DIRECT_MISSING"),
		NextOperation: "PROVIDE_WORKSPACE_ROOT",
		BlockedBy:     []string{"workspace-root"},
	}
	return report
}

func refuted(report Report, stage, step, reason, nextOperation string) Report {
	report.Decision = "FAIL_CLOSED"
	report.Claim = Claim{
		State:         "REFUTED",
		Stage:         new(stage),
		Step:          new(step),
		Reason:        reason,
		NextOperation: nextOperation,
		BlockedBy:     []string{"workspace-root"},
	}
	return report
}

func languageFor(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".go":
		return "GO"
	case ".gooo":
		return "GOOO"
	default:
		return "OTHER"
	}
}

func countLines(path string) (int, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	buffer := make([]byte, 32*1024)
	lines := 0
	totalBytes := 0
	lastByte := byte('\n')
	for {
		read, readErr := file.Read(buffer)
		if read > 0 {
			chunk := buffer[:read]
			lines += bytes.Count(chunk, []byte{'\n'})
			totalBytes += read
			lastByte = chunk[len(chunk)-1]
		}
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return 0, readErr
		}
	}
	if totalBytes > 0 && lastByte != '\n' {
		lines++
	}
	return lines, nil
}
