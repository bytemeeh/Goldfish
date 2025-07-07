import { pino } from 'pino';

const logger = pino();

export const logJson = (res: any, body: unknown) => {
  if (res.headersSent) return;
  const b = JSON.stringify(body);
  logger.info({ 
    payload: b.length <= 80 ? b : b.slice(0, 77) + '…' 
  }, 'response');
};

export { logger };