import express from 'express';
import helmet from 'helmet';

import { createRollNumberController } from './controllers/roll_number_controller.js';
import { createErrorHandler, notFoundHandler } from './middleware/error_handler.js';
import { createRateLimiters } from './middleware/rate_limiter.js';
import { requestLogger } from './middleware/request_logger.js';
import { requestTimeout } from './middleware/request_timeout.js';
import { createHealthRouter } from './routes/health_routes.js';
import { createRollNumberRouter } from './routes/roll_number_routes.js';
import { RollNumberService } from './services/roll_number_service.js';
import { JsonFileStorage } from './storage/json_file_storage.js';
import { createLogger } from './utils/logger.js';
import { createRollNumberValidator } from './utils/roll_number.js';

/**
 * Builds the Express application. Dependencies can be injected for tests;
 * otherwise they are created from `config`.
 */
export function createApp({ config, storage, logger = createLogger(config.logLevel) }) {
  const service = new RollNumberService({
    storage: storage ?? new JsonFileStorage(config.dataFilePath),
    normalizeRollNumber: createRollNumberValidator({
      pattern: config.rollNumberPattern,
      maxLength: config.rollNumberMaxLength,
    }),
  });
  const controller = createRollNumberController({ service, logger });
  const limiters = createRateLimiters(config.rateLimit);

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  app.use(helmet());
  app.use((_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });
  app.use(requestTimeout(config.requestTimeoutMs));
  app.use(requestLogger(logger));
  app.use(express.json({ limit: config.bodyLimit, strict: true }));

  app.use('/api/health', createHealthRouter({ service }));
  app.use('/api/roll-numbers', createRollNumberRouter({ controller, config, limiters }));

  app.use(notFoundHandler);
  app.use(createErrorHandler(logger));

  return app;
}
