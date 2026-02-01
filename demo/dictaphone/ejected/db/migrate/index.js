import { migration as migration0 } from './20260127145356_create_clips.js';
import { migration as migration1 } from './20260127145357_create_active_storage_tables.active_storage.js';
export const migrations = [{ version: '20260127145356', name: '20260127145356_create_clips', ...migration0 }, { version: '20260127145357', name: '20260127145357_create_active_storage_tables.active_storage', ...migration1 }];
