## ADDED Requirements

### Requirement: Open a project tree for a system

The system SHALL provide an "Open project" command that lets the user select a
registered ASDF system and opens a project window showing that system's
components as a collapsible tree. Modules SHALL appear as expandable nodes and
source files as leaf nodes. The tree SHALL be derived from the system's own ASDF
components, and each source-file leaf SHALL indicate whether that file is
currently open in an editor window.

#### Scenario: Open the project window for a system

- **WHEN** the user invokes "Open project" and selects a registered system
- **THEN** a project window opens containing a tree whose root is the system,
  with its modules as expandable nodes and its source files as leaves
- **AND** each source-file leaf is marked as open or closed according to whether
  an editor window currently backs that file

#### Scenario: System selection cancelled

- **WHEN** the user invokes "Open project" and cancels the system picker
- **THEN** no project window is opened

#### Scenario: System components cannot be read

- **WHEN** the user selects a system whose components cannot be enumerated
- **THEN** no project window is opened
- **AND** an informational message states that the system's components could not
  be read

### Requirement: Open the file at the cursor

The project window SHALL open the source file of the focused leaf node in an
editor window when the user activates it. If an editor window already backs that
file, the command SHALL focus that existing window instead of opening a second
one. After the action, the file's open/closed marker SHALL be updated.

#### Scenario: Activate a closed file

- **WHEN** the user activates a file leaf whose file has no editor window
- **THEN** an editor window opens for that file and the leaf is marked open

#### Scenario: Activate an already-open file

- **WHEN** the user activates a file leaf whose file already has an editor window
- **THEN** that existing window is focused and no second window is opened

### Requirement: Open all files under a node

The project window SHALL provide a command that opens every source file beneath
the focused node — the whole system at the root, a single module, or one file —
in editor windows. Files that already have an editor window SHALL be reused, not
duplicated. The newly opened windows SHALL be arranged so they do not completely
overlap, and a summary SHALL report the number opened and the number already
open.

#### Scenario: Open every file of a system

- **WHEN** the focused node is the system root and the user issues "open all"
- **THEN** an editor window is opened for each of the system's source files that
  is not already open
- **AND** files that were already open are reused rather than duplicated
- **AND** a summary reports the count opened and the count already open

#### Scenario: Open the files of one module

- **WHEN** the focused node is a module and the user issues "open all"
- **THEN** only that module's source files are opened (other modules are
  untouched)

#### Scenario: Node has no source files

- **WHEN** the user issues "open all" on a node with no source files beneath it
- **THEN** no windows are opened
- **AND** an informational message states there are no source files under the
  node

### Requirement: Skip missing or unreadable files

When opening files, the system SHALL skip files that do not exist on disk or
cannot be opened, without aborting the operation, and MUST continue opening the
remaining files under the node.

#### Scenario: A component file is missing on disk

- **WHEN** "open all" is issued on a node one of whose files is missing or
  unreadable
- **THEN** the remaining files are still opened
- **AND** the skipped file does not abort the operation

### Requirement: Close all files under a node

The project window SHALL provide a command that closes every editor window whose
backing file is a source file beneath the focused node. Editor windows for files
not under the node, and non-editor windows (such as REPLs), SHALL remain open. A
summary SHALL report how many windows were closed.

#### Scenario: Close a system's windows

- **WHEN** the focused node is the system root and the user issues "close all"
- **THEN** every editor window backed by one of the system's source files is
  closed
- **AND** windows for unrelated files and non-editor windows remain open
- **AND** a summary reports how many windows were closed

#### Scenario: No matching windows are open

- **WHEN** the user issues "close all" on a node none of whose files are open
- **THEN** no windows are closed

### Requirement: Preserve unsaved changes on close

Closing windows from the project window SHALL route each window's closure through
the existing unsaved-changes guard, so a window with unsaved edits prompts the
user to save, discard, or cancel before it closes.

#### Scenario: A window has unsaved changes

- **WHEN** "close all" attempts to close an editor window that has unsaved changes
- **THEN** the user is prompted to save, discard, or cancel that window
- **AND** choosing cancel keeps that window open while the other matching windows
  still close

### Requirement: Refresh the tree from ASDF

The project window SHALL provide a command that re-reads the system from ASDF and
rebuilds the tree, so that changes to the system definition (such as files added
to the `.asd`) are reflected without reopening the window.

#### Scenario: Rebuild after a system-definition change

- **WHEN** the user issues "refresh" in the project window
- **THEN** the tree is rebuilt from the system's current ASDF components
- **AND** the open/closed markers reflect the current set of editor windows
