package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInitAndRegisterScopedRoots(t *testing.T) {
	state := t.TempDir()
	if err := execute([]string{"init", "--state-root", state}); err != nil {
		t.Fatal(err)
	}
	workspace := filepath.Join(t.TempDir(), "workspace")
	project := filepath.Join(workspace, "project")
	if err := os.MkdirAll(project, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := execute([]string{"registry", "add-workspace", "--state-root", state, "--root", workspace, "--instance", "workspace-main"}); err != nil {
		t.Fatal(err)
	}
	if err := execute([]string{"registry", "add-project", "--state-root", state, "--workspace-root", workspace, "--root", project, "--instance", "project-main"}); err != nil {
		t.Fatal(err)
	}
	r, _, err := loadRegistry(state)
	if err != nil {
		t.Fatal(err)
	}
	if r.Global.Instance != "global" || len(r.Workspaces) != 1 || len(r.Workspaces[0].Projects) != 1 {
		t.Fatalf("unexpected registry: %#v", r)
	}
}

func TestDeckKeepsStandaloneCardsIndependent(t *testing.T) {
	cards, err := resolveCards("scry,trace")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"scry", "trace"}
	if len(cards) != len(want) {
		t.Fatalf("cards=%v want=%v", cards, want)
	}
	for i := range want {
		if cards[i] != want[i] {
			t.Fatalf("cards=%v want=%v", cards, want)
		}
	}
}

func TestDoctorVerifiesEverySelectedCard(t *testing.T) {
	bundle, state := t.TempDir(), t.TempDir()
	if err := execute([]string{"init", "--state-root", state}); err != nil {
		t.Fatal(err)
	}
	paths := []string{
		"apps/lexicon/application/pulp.app.toml", "apps/splice/application/pulp.app.toml", "apps/splice/engines/bounded-transform-cell/bounded-transform.wasm",
		"apps/scry/application/pulp.app.toml", "apps/trace/application/pulp.app.toml", "apps/lens/nvim/lua/inspector/init.lua",
		"apps/pulp-engines/lifecycle-cell/lifecycle-evaluator.wasm", "apps/pulp-engines/receipt-sqlite-cell/receipt-sqlite.wasm", "apps/Pulp-Lua/pulp-cell/lua-orchestrator.wasm",
	}
	for _, name := range []string{"aideck", "lexicon-mcp", "lexicon-codex", "splice", "splice-mcp", "scry", "trace", "lens", "lens-mcp", "atlas"} {
		paths = append(paths, filepath.Join("bin", executable(name)))
	}
	for _, path := range paths {
		full := filepath.Join(bundle, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("ok"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := execute([]string{"doctor", "--bundle-root", bundle, "--state-root", state, "--cards", "lexicon,splice,scry,trace,lens,atlas"}); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(bundle, "bin", executable("atlas"))); err != nil {
		t.Fatal(err)
	}
	if err := execute([]string{"doctor", "--bundle-root", bundle, "--state-root", state, "--cards", "atlas"}); err == nil || !strings.Contains(err.Error(), "atlas") {
		t.Fatalf("doctor should reject a missing selected Atlas launcher, got %v", err)
	}
}

func TestSetupNvimCreatesOnlySelectedLensAdapter(t *testing.T) {
	root := t.TempDir()
	plugin := filepath.Join(root, "lens")
	splice := filepath.Join(root, "splice")
	if err := execute([]string{"setup", "nvim", "--cards", "lens,splice", "--nvim-config", root, "--lens-plugin", plugin, "--splice-plugin", splice}); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(root, "lua", "plugins", "aideck.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if got := string(b); !strings.Contains(got, "LensOpen") || !strings.Contains(got, "aideck-lens.nvim") || !strings.Contains(got, "aideck-splice.nvim") || !strings.Contains(got, "require('splice').edit") {
		t.Fatalf("unexpected plugin spec: %s", got)
	}
}
