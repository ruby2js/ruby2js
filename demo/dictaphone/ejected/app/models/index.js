import { Clip } from './clip.js';
import { Application } from 'ruby2js-rails/targets/node/rails.js';
import { modelRegistry } from 'ruby2js-rails/adapters/active_record_better_sqlite3.mjs';
const models = { Clip };
Application.registerModels(models);
Object.assign(modelRegistry, models);
export { Clip };
