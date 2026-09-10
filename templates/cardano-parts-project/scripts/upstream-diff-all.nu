#!/usr/bin/env nu
#
# upstream-diff-all: batch pull upstream cardano-parts template changes into
# this downstream repo. Run from the downstream repo root.
#
# Flow:
#   1. Collect changed template files in the upstream cardano-parts repo
#      (git diff --name-only <ref>, limited to templates/cardano-parts-project),
#      drop anything matched by ./.upstream-diff-all.excludes, and classify
#      the remainder against this repo's files.
#   2. Curate the annotated file list in $EDITOR; delete or comment out lines
#      to skip those files.
#   3. Files not yet in this repo are offered for copy (y/n). Every other
#      curated file pair opens in a two-pane diff editor: local file on the
#      left, upstream template file on the right - edit the local file
#      directly and save. The tool is $UPSTREAM_DIFF_CMD if set, else
#      $DIFFPROG, else `nvim -d`, invoked as: <tool> <local-file> <template-file>
#
# The upstream path may be the cardano-parts repo root or its
# templates/cardano-parts-project directory (the TEMPLATE_PATH convention).
#
# Abort at either editor stage by exiting with an error (:cq in vim).
# Changes are left unstaged for review with `git diff` / `git add -p`.
const EXCLUDES_NAME = ".upstream-diff-all.excludes"
const STATUSES = ["M", "N", "D", "I", "X"]
# Resolve the editor, honoring flags embedded in $EDITOR (e.g. "code --wait").
# Returns false when the editor exits non-zero so callers can abort.
def edit-file [file: path] {
  let editor = ($env.EDITOR? | default "" | str trim)
  let editor = if $editor == "" { "nvim" } else { $editor }
  let editor_parts = ($editor | split row " " | where $it != "")
  try {
    run-external ($editor_parts | first) ...($editor_parts | skip 1) $file
    true
  } catch {
    false
  }
}
def classify [file: string, template_dir: path] {
  let template_file = ($template_dir | path join $file)
  let template_file_exists = ($template_file | path exists)
  let local_file_exists = ($file | path exists)
  let status = if not $template_file_exists {
    if $local_file_exists { "D" } else { "X" }
  } else if not $local_file_exists {
    "N"
  } else if (do { ^cmp -s $template_file $file } | complete | get exit_code) == 0 {
    "I"
  } else {
    "M"
  }
  let dirty = ($local_file_exists and (
    do { ^git status --porcelain -- $file } | complete | get stdout | str trim | is-not-empty
  ))
  {
    file: $file
    status: $status
    dirty: $dirty
  }
}
# Subject of the last upstream branch commit (vs <ref>) touching the file - a
# hint for grouping pulled changes into discrete local commits.
def last-commit [file: string, template_dir: path, ref: string] {
  let subject = (
    do { ^git -C $template_dir log -1 --no-color --format="%h %s" $"($ref)..HEAD" -- $file } | complete | get stdout | str trim | lines | get 0? | default ""
  )
  let subject = if $subject == "" { "(uncommitted)" } else { $subject }
  if ($subject | str length) > 80 { ($subject | str substring 0..<80) + "..." } else { $subject }
}
# Copy new files into this repo and open each remaining file pair in a
# two-pane diff editor, editing the local file directly - changes land
# immediately, with no patch/apply step.
def pairwise-diff [curated_files: list<string>, template_dir: path] {
  # Tool lookup order: explicit override, then the conventional two-pane diff
  # program variable (as used by pacdiff and friends), then nvim -d
  let diff_cmd = (
    [
      ($env.UPSTREAM_DIFF_CMD? | default "")
      ($env.DIFFPROG? | default "")
      "nvim -d"
    ] | each {|candidate| $candidate | str trim} | where {|candidate| $candidate != ""} | first
  )
  let diff_cmd_parts = ($diff_cmd | split row " " | where $it != "")
  let total_count = ($curated_files | length)
  print $"Pairwise diff of ($total_count) files with '($diff_cmd)': local left, template right."
  print "Edit the local pane, then save and quit \(:wqa) for the next file; quit with an error \(:cq) to abort."
  mut summary = []
  for entry in ($curated_files | enumerate) {
    let file = $entry.item
    let template_file = ($template_dir | path join $file)
    if not ($template_file | path exists) {
      $summary = ($summary | append {file: $file, result: "skipped", detail: "deleted upstream; remove the local file manually if desired"})
      continue
    }
    if not ($file | path exists) {
      # New to this repo: no diff to resolve, offer to copy it over
      let answer = (input $"[($entry.index + 1)/($total_count)] ($file) - new to this repo; copy? [Y/n] ")
      if ($answer | str downcase | str starts-with "n") {
        $summary = ($summary | append {file: $file, result: "skipped", detail: "copy declined"})
        continue
      }
      mkdir ($file | path dirname)
      cp $template_file $file
      $summary = ($summary | append {file: $file, result: "copied", detail: ""})
      continue
    }
    let hash_before = (open --raw $file | hash sha256)
    print $"[($entry.index + 1)/($total_count)] ($file)"
    let editor_succeeded = (try {
      run-external ($diff_cmd_parts | first) ...($diff_cmd_parts | skip 1) $file $template_file
      true
    } catch {
      false
    })
    if not $editor_succeeded {
      $summary = ($summary | append {file: $file, result: "aborted", detail: "editor exited with an error"})
      break
    }
    let file_result = if (open --raw $file | hash sha256) == $hash_before {
      {
        file: $file
        result: "unchanged"
        detail: ""
      }
    } else {
      {
        file: $file
        result: "modified"
        detail: ""
      }
    }
    $summary = ($summary | append $file_result)
  }
  print ""
  print $summary
  let unvisited_count = ($total_count - ($summary | length))
  if $unvisited_count > 0 {
    print $"($unvisited_count) files not visited due to abort."
  }
  if ($summary | where result in ["copied", "modified"] | length) > 0 {
    print "Review the local changes with: git diff   \(then git add -p)"
  }
}
def main [
  upstream: string = "no-path-given"  # path to the upstream cardano-parts repo (or its template dir)
  --ref: string = "main"              # base ref for the upstream diff
] {
  if $upstream == "no-path-given" {
    print -e "No upstream path given. Pass one as an argument or set TEMPLATE_PATH."
    exit 1
  }
  if not ($upstream | path exists) {
    print -e $"Upstream path not found: ($upstream)"
    exit 1
  }
  # Accept either the cardano-parts repo root or the template dir itself
  let template_dir = if ($upstream | path join "templates/cardano-parts-project" | path exists) {
    $upstream | path join "templates/cardano-parts-project"
  } else {
    $upstream
  }
  if not ($template_dir | path join "Justfile" | path exists) {
    print -e $"($template_dir) does not look like the cardano-parts template; expected a Justfile in it."
    exit 1
  }
  # Template file paths relative to the upstream repo root, e.g.
  # "templates/cardano-parts-project/", for stripping from git diff output
  let show_prefix_result = (do { ^git -C $template_dir rev-parse --show-prefix } | complete)
  if $show_prefix_result.exit_code != 0 {
    print -e $"($template_dir) is not inside a git checkout of cardano-parts."
    exit 1
  }
  let template_path_prefix = ($show_prefix_result.stdout | str trim)
  # This repo declares its never-pulled paths in an excludes file
  let excludes_file = $EXCLUDES_NAME
  let exclude_patterns = if ($excludes_file | path exists) {
    open --raw $excludes_file | lines | each {|line| $line | str trim} | where {|line| $line != "" and not ($line | str starts-with "#")}
  } else {
    []
  }
  let all_changed_files = (
    ^git -C $template_dir diff --name-only $ref -- "." | lines | where {|line| ($line | str trim) != ""} | each {|line| $line | str replace $template_path_prefix ""}
  )
  if ($all_changed_files | is-empty) {
    print $"No upstream template changes vs '($ref)'."
    return
  }
  # The excludes file itself is never pulled; pathspecs are relative to the
  # template dir since git runs with -C into it
  let exclude_pathspecs = ($exclude_patterns | append $EXCLUDES_NAME | each {|pattern| ":(exclude)" + $pattern})
  let changed_files = (
    ^git -C $template_dir diff --name-only $ref -- "." ...$exclude_pathspecs | lines | where {|line| ($line | str trim) != ""} | each {|line| $line | str replace $template_path_prefix ""}
  )
  let excluded_count = (($all_changed_files | length) - ($changed_files | length))
  print $"Classifying ($changed_files | length) changed files against this repo..."
  let classified_files = ($changed_files | each {|file| classify $file $template_dir})
  let identical_count = ($classified_files | where status == "I" | length)
  let noop_count = ($classified_files | where status == "X" | length)
  let status_sort_order = {M: 0, N: 1, D: 2}
  let list_entries = (
    $classified_files | where status in ["M", "N", "D"] | sort-by {|entry| $status_sort_order | get $entry.status} | each {|entry| $entry | insert commit (last-commit $entry.file $template_dir $ref)}
  )
  if ($list_entries | is-empty) {
    print "Nothing to pull: all upstream changes are excluded, already in this repo, or no-ops."
    return
  }
  # --- Step 1: curate the file list ---------------------------------------
  let temp_dir = (mktemp --directory --tmpdir "upstream-diff-all.XXXXXX")
  let list_file = ($temp_dir | path join "1-file-list")
  let skip_notes = ([
    (if $excluded_count > 0 {
      $"#   ($excluded_count) matched by ($EXCLUDES_NAME) in this repo"
    })
    (if not ($excludes_file | path exists) {
      $"#   \(auto-exclude files by creating ($excludes_file) with one git pathspec per line)"
    })
    (if $identical_count > 0 {
      $"#   ($identical_count) already identical to this repo's copy"
    })
    (if $noop_count > 0 {
      $"#   ($noop_count) in neither the upstream template nor this repo - nothing to do"
    })
  ] | where {|note| $note != null})
  mut list_legend = [
    "# upstream-diff-all - step 1/2: curate the file list"
    $"# Upstream: ($template_dir) \(diffed against '($ref)')"
    "#"
    "# Keep a line to pull that file; delete or comment it out to skip it."
    "#   M  differs from this repo's copy - opens in the pairwise diff editor"
    "#   N  not in this repo - prompts to copy it over"
    "#   D  deleted upstream - skipped; remove the local file manually"
    "# After each file: the last upstream branch commit touching it, as a commit-grouping hint."
    "# Lines whose local file has uncommitted git changes start disabled."
    "# Save and quit to continue; quit with an error \(:cq in vim) to abort."
  ]
  if not ($skip_notes | is-empty) {
    $list_legend = ($list_legend | append "# Not listed:" | append $skip_notes)
  }
  $list_legend = ($list_legend | append "#")
  let file_column_width = (
    $list_entries | get file | each {|file| $file | str length} | math max
  )
  let list_body = ($list_entries | each {|entry|
    let line = $"($entry.status) ($entry.file | fill --alignment left --character ' ' --width $file_column_width)  # ($entry.commit)"
    if $entry.dirty {
      $"# ($line)  <- local file dirty in git; commit or revert it first"
    } else {
      $line
    }
  })
  $list_legend | append $list_body | str join "\n" | $"($in)\n" | save -f $list_file
  if not (edit-file $list_file) {
    print "Aborted: editor exited with an error."
    return
  }
  let curated_files = (
    open --raw $list_file | lines | each {|line| $line | str trim} | where {|line| $line != "" and not ($line | str starts-with "#")} | each {|line|
        let tokens = ($line | split row --regex '\s+')
        if ($tokens | length) >= 2 and (($tokens | first) in $STATUSES) {
          $tokens | get 1
        } else {
          $tokens | first
        }
      } | uniq
  )
  if ($curated_files | is-empty) {
    print "No files selected; nothing to do."
    return
  }
  pairwise-diff $curated_files $template_dir
}
