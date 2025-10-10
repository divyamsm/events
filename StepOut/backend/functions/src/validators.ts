import { HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

export function parseRequest<T>(schema: z.ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpsError("invalid-argument", result.error.issues.map((issue) => issue.message).join("; "));
  }
  return result.data;
}
