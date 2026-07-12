import type { Actions } from './$types';
import { requestMagicLink } from '$lib/server/auth';

export const actions: Actions = { default: requestMagicLink };
