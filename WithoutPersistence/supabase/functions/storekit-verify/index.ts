import { context } from '../_shared/storekit-runtime.ts';
import { purchaseHandler } from '../_shared/storekit-http.mjs';
Deno.serve(purchaseHandler(context));
