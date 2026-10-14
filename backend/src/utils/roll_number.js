import { AppError } from '../errors.js';

/**
 * Builds the server-side normaliser/validator. The server is the source of
 * truth: every value is trimmed, upper-cased and checked here regardless of
 * what the client already did.
 */
export function createRollNumberValidator({ pattern, maxLength }) {
  return function normalizeRollNumber(value) {
    if (typeof value !== 'string') {
      throw new AppError(400, 'ROLL_NUMBER_REQUIRED', 'rollNumber is required and must be a string');
    }

    // toUpperCase() is locale-independent in JavaScript, unlike toLocaleUpperCase().
    const normalized = value.trim().toUpperCase();

    if (normalized.length === 0) {
      throw new AppError(400, 'ROLL_NUMBER_EMPTY', 'Registration number must not be empty');
    }
    if (normalized.length > maxLength) {
      throw new AppError(400, 'ROLL_NUMBER_TOO_LONG', `Registration number must be at most ${maxLength} characters`);
    }
    if (!pattern.test(normalized)) {
      throw new AppError(400, 'ROLL_NUMBER_INVALID', 'Registration number format is invalid');
    }
    return normalized;
  };
}
