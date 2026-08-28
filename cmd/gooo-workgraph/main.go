package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/kimjooyoon/gooo-workgraph/internal/inventory"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] != "observe" {
		fmt.Fprintln(stderr, "usage: gooo-workgraph observe --root PATH [--json]")
		return 2
	}

	flags := flag.NewFlagSet("observe", flag.ContinueOnError)
	flags.SetOutput(stderr)
	root := flags.String("root", ".", "workspace root to observe")
	jsonOutput := flags.Bool("json", false, "emit versioned JSON")
	if err := flags.Parse(args[1:]); err != nil {
		return 2
	}
	if flags.NArg() != 0 {
		fmt.Fprintln(stderr, "observe accepts flags only")
		return 2
	}

	report := inventory.Observe(*root)
	if !*jsonOutput {
		fmt.Fprintf(stdout,
			"%s state=%s directories=%d files=%d go=%d/%d gooo=%d/%d root_readme_required=false\n",
			report.Decision,
			report.Claim.State,
			report.Summary.Directories,
			report.Summary.Files,
			report.Summary.GoFiles,
			report.Summary.GoLines,
			report.Summary.GoooFiles,
			report.Summary.GoooLines,
		)
		return 0
	}

	encoder := json.NewEncoder(stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(report); err != nil {
		fmt.Fprintf(stderr, "encode observation: %v\n", err)
		return 1
	}
	return 0
}
