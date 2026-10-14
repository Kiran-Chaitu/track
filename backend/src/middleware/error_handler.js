import { AppError, StorageError } from '../errors.js';
import { sendError } from '../utils/http.js';

export function notFoundHandler(_req, res) {
  sendError(res, 404, 'NOT_FOUND', 'Route not found');
}

/**
 * Converts errors into JSON responses. Internal details (paths, stack traces,
 * environment) are logged server-side only and never sent to the client.
 */
export function createErrorHandler(logger) {
  // Express identifies error handlers by their four-argument signature.
  // eslint-disable-next-line no-unused-vars
  return function errorHandler(err, req, res, _next) {
    if (res.headersSent) {
      logger.warn('Error after response was sent', { path: req.path, error: err.message });
      return;
    }

    if (err instanceof AppError) {
      return sendError(res, err.status, err.code, err.message);
    }

    // Errors raised by express.json() / body-parser.
    if (err.type === 'entity.too.large') {
      return sendError(res, 413, 'PAYLOAD_TOO_LARGE', 'Request body is too large');
    }
    if (err.type === 'entity.parse.failed') {
      return sendError(res, 400, 'INVALID_JSON', 'Request body is not valid JSON');
    }
    if (typeof err.status === 'number' && err.status >= 400 && err.status < 500) {
      return sendError(res, err.status, 'BAD_REQUEST', 'Bad request');
    }

    if (err instanceof StorageError) {
      logger.error('Storage failure', { code: err.code, error: err.message });
      return sendError(
        res,
        503,
        'STORAGE_UNAVAILABLE',
        'Registration storage is temporarily unavailable. Please try again later.',
      );
    }

    logger.error('Unhandled error', { error: err.message, stack: err.stack });
    return sendError(res, 500, 'INTERNAL_ERROR', 'An unexpected server error occurred');
  };
}
