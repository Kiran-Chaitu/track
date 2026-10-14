import { AppError } from '../errors.js';
import { sendJson } from '../utils/http.js';

export function createRollNumberController({ service, logger }) {
  return {
    async create(req, res) {
      if (!req.is('application/json')) {
        throw new AppError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Content-Type must be application/json');
      }
      const body = req.body;
      if (body === null || typeof body !== 'object' || Array.isArray(body)) {
        throw new AppError(400, 'INVALID_BODY', 'Request body must be a JSON object');
      }

      const { rollNumber, duplicate } = await service.register(body.rollNumber);

      // Registration numbers are intentionally not logged.
      logger.info(duplicate ? 'Duplicate registration received' : 'Registration stored');

      sendJson(res, duplicate ? 200 : 201, {
        success: true,
        message: duplicate ? 'Registration number already exists' : 'Registration number stored successfully',
        rollNumber,
        duplicate,
      });
    },

    async list(_req, res) {
      const rollNumbers = await service.list();
      sendJson(res, 200, { success: true, count: rollNumbers.length, rollNumbers });
    },

    async count(_req, res) {
      sendJson(res, 200, { success: true, count: await service.count() });
    },
  };
}
