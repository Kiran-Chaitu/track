/** An error whose status, code and message are safe to send to clients. */
export class AppError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
  }
}

/**
 * A storage failure. `code` is STORAGE_CORRUPT (the file exists but cannot be
 * trusted) or STORAGE_IO (filesystem error). The message may contain paths and
 * must only be logged, never returned to clients.
 */
export class StorageError extends Error {
  constructor(code, message, options) {
    super(message, options);
    this.name = 'StorageError';
    this.code = code;
  }
}
