# Word to PDF File or Folder Conversion Design

## Goal

Simplify `bat/word_to_pdf.bat` so the user enters one Word file or one folder path. A file input converts only that document; a folder input recursively finds supported documents. Every generated PDF is written beside its source document.

## User interaction

1. Display one prompt requesting a Word file or folder path.
2. Accept a path with or without surrounding double quotes.
3. Do not ask for an output folder or whether to recurse.
4. Reject an empty path, a missing path, or a file with an unsupported extension.

## Conversion behavior

- Convert a supported file input directly.
- Recursively scan a selected folder and all subfolders.
- Support `.doc`, `.docx`, `.docm`, `.rtf`, and `.odt`, matching current behavior.
- For every source document, create `<source-name>.pdf` in that document's own folder.
- Replace an existing same-name PDF with the newly converted result.
- Continue using Microsoft Word when available, otherwise LibreOffice/OpenOffice.
- Keep per-file failure reporting and continue processing the remaining files.

## Downloaded document handling

- Detect whether a source document has a `Zone.Identifier` alternate data stream.
- For a marked document, copy it to a unique temporary directory and remove the security marker from the temporary copy only.
- Open the temporary copy in Microsoft Word, but derive the PDF name and destination from the original source document.
- Delete the temporary copy and directory after the document succeeds or fails.
- Do not change the original document, including its content, timestamps, or security marker.
- Open an unmarked local document directly without creating a temporary copy.

## Implementation shape

- The batch portion sets only `WORD2PDF_INPUT`; output and recursion environment variables are removed.
- The embedded PowerShell branches on the resolved input item: a directory enumerates with `AllDirectories`; a supported file becomes a one-item file list.
- Conversion functions derive the target directory from each `FileInfo.DirectoryName` rather than accepting one shared target directory.
- LibreOffice receives each source document's directory as its `--outdir` value.
- Microsoft Word receives either the original path or an unblocked temporary-copy path while retaining the original `FileInfo` for output naming.

## Error handling

- Empty input: report that a file or folder path is required.
- Missing input: report that the path does not exist.
- Unsupported file input: report the unsupported extension.
- No supported documents: report that none were found.
- Converter unavailable: retain the existing installation error.

## Verification

- Confirm a quoted file containing spaces and Chinese characters is accepted as a one-file conversion target.
- Confirm a quoted folder containing spaces and Chinese characters reaches PowerShell unchanged except for removed wrapping quotes.
- Confirm nested supported documents are discovered.
- Confirm output paths are derived from each document's own directory.
- Confirm unsupported file input is rejected.
- Confirm a marked source selects an unblocked temporary copy and leaves the original `Zone.Identifier` intact.
- Confirm temporary files are removed after both successful and failed Word opens.
- Confirm an unmarked source is opened directly.
- Run a syntax check over the embedded PowerShell payload and a controlled conversion when a suitable test document is available.
