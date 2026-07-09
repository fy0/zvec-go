//go:build purego

package zvec

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestPuregoLibraryCandidatesPreferEnvFile(t *testing.T) {
	envPath := filepath.Join(t.TempDir(), "custom-zvec")
	t.Setenv(zvecLibraryPathEnv, envPath)

	candidates := zvecLibraryCandidates()
	if len(candidates) == 0 {
		t.Fatal("zvecLibraryCandidates returned no candidates")
	}
	if candidates[0] != envPath {
		t.Fatalf("first candidate = %q, want env path %q", candidates[0], envPath)
	}
}

func TestPuregoLibraryCandidatesPreferEnvDir(t *testing.T) {
	envDir := t.TempDir()
	t.Setenv(zvecLibraryPathEnv, envDir)

	candidates := zvecLibraryCandidates()
	if len(candidates) == 0 {
		t.Fatal("zvecLibraryCandidates returned no candidates")
	}
	want := filepath.Join(envDir, zvecLibraryNames()[0])
	if candidates[0] != want {
		t.Fatalf("first candidate = %q, want env dir library %q", candidates[0], want)
	}
}

func TestPuregoInitializeSmoke(t *testing.T) {
	t.Setenv(zvecLibraryPathEnv, filepath.Join(t.TempDir(), zvecLibraryNames()[0]))

	err := Initialize(nil)
	if err == nil {
		if shutdownErr := Shutdown(); shutdownErr != nil {
			t.Fatalf("Shutdown after successful purego Initialize failed: %v", shutdownErr)
		}
		return
	}

	message := err.Error()
	if !strings.Contains(message, zvecLibraryPathEnv) {
		t.Fatalf("Initialize error %q does not mention %s", message, zvecLibraryPathEnv)
	}
	if !strings.Contains(message, zvecLibraryNames()[0]) {
		t.Fatalf("Initialize error %q does not mention expected library name %s", message, zvecLibraryNames()[0])
	}
}
