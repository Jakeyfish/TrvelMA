import { context } from '../_shared/storekit-runtime.ts';
import { notificationHandler } from '../_shared/storekit-http.mjs';
// Apple signs notifications; this endpoint does not trust a caller-supplied owner.
Deno.serve(notificationHandler(context));
