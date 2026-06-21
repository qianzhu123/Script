# Word to PDF Folder Conversion Design

## Goal

Simplify `bat/word_to_pdf.bat` so the user only enters one folder path. The script recursively finds supported Word documents and writes each generated PDF beside its source document.

## User interaction

1. Display one prompt requesting a document folder path.
2. Accept a path with or without surrounding double quotes.
3. Do not ask for an output folder or whether to recurse.
4. Reject an empty path, a missing path, or a path that points to a file.

## Conversion behavior

- Recursively scan the selected folder and all subfolders.
- Support `.doc`, `.docx`, `.docm`, `.rtf`, and `.odt`, matching current behavior.
- For every source document, create `<source-name>.pdf` in that document's own folder.
- Replace an existing same-name PDF with the newly converted result.
- Continue using Microsoft Word when available, otherwise LibreOffice/OpenOffice.
- Keep per-file failure reporting and continue processing the remaining files.

## Implementation shape

- The batch portion sets only `WORD2PDF_INPUT`; output and recursion environment variables are removed.
- The embedded PowerShell requires the resolved input item to be a directory and always enumerates with `AllDirectories`.
- Conversion functions derive the target directory from each `FileInfo.DirectoryName` rather than accepting one shared target directory.
- LibreOffice receives each source document's directory as its `--outdir` value.

## Error handling

- Empty input: report that a folder path is required.
- Missing input: report that the folder does not exist.
- File input: report that a folder is required.
- No supported documents: report that none were found.
- Converter unavailable: retain the existing installation error.

## Verification

- Confirm a quoted folder containing spaces and Chinese characters reaches PowerShell unchanged except for removed wrapping quotes.
- Confirm nested supported documents are discovered.
- Confirm output paths are derived from each document's own directory.
- Confirm file input is rejected.
- Run a syntax check over the embedded PowerShell payload and a controlled conversion when a suitable test document is available.
