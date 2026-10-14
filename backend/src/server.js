import { createApp } from './app.js';
import { ConfigError, loadConfig } from './config.js';
import { JsonFileStorage } from './storage/json_file_storage.js';
import { createLogger } from './utils/logger.js';

const SHUTDOWN_GRACE_MS = 10_000;

async function main() {
  let config;
  try {
    config = loadConfig();
  } catch (err) {
    if (err instanceof ConfigError) {
      console.error(`Configuration error: ${err.message}`);
      process.exit(1);
    }
    throw err;
  }

  const logger = createLogger(config.logLevel);
  const storage = new JsonFileStorage(config.dataFilePath);

  // A broken data file must not be overwritten, so the server still starts
  // (health stays reachable) and storage operations return 503 until fixed.
  try {
    const { count } = await storage.init();
    logger.info('Storage ready', { file: config.dataFilePath, count });
  } catch (err) {
    logger.error('Storage initialisation failed; writes will be rejected until it is fixed', {
      code: err.code,
      error: err.message,
    });
  }

  if (!config.adminApiKey) {
    logger.warn('ADMIN_API_KEY is not set; administrative endpoints are disabled');
  } else if (config.adminApiKey.length < 24) {
    logger.warn('ADMIN_API_KEY is short; use at least 32 random characters');
  }
  if (config.isProduction && !config.ingestApiKey) {
    logger.warn('INGEST_API_KEY is not set; anyone who knows the URL can submit registration numbers');
  }

  const app = createApp({ config, storage, logger });
  const server = app.listen(config.port, config.host, () => {
    const { port } = server.address();
    logger.info('Server listening', { host: config.host, port, env: config.nodeEnv });
  });
  server.headersTimeout = 20_000;
  server.requestTimeout = 30_000;

  let shuttingDown = false;
  const shutdown = (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info('Shutting down', { signal });

    const force = setTimeout(() => {
      logger.error('Forced shutdown after timeout');
      process.exit(1);
    }, SHUTDOWN_GRACE_MS);
    force.unref();

    server.close(async () => {
      await storage.drain();
      logger.info('Shutdown complete');
      process.exit(0);
    });
    server.closeIdleConnections();
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection', { error: String(reason) });
  });
}

main().catch((err) => {
  console.error('Fatal startup error', err);
  process.exit(1);
});
