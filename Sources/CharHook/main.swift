import Foundation
import CharCore

// Official hook JSON ingestion is provided by the observation adapter.
FileHandle.standardError.write(Data("char-hook: hook adapter is not installed yet.\n".utf8))
exit(1)
