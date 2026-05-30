import { HttpsError } from "firebase-functions/v2/https";

/** gRPC status code from @google-cloud/* clients. */
export function grpcStatusCode(error: unknown): number | undefined {
  const code = (error as { code?: number }).code;
  return typeof code === "number" ? code : undefined;
}

export function secretManagerSetupErrorMessage(projectId: string): string {
  return (
    "Could not save LarpManager credentials in Google Secret Manager. " +
    "Enable the Secret Manager API and grant the Cloud Functions runtime " +
    "service account roles/secretmanager.admin (or Secret Manager Admin) on " +
    `project ${projectId}. See FIREBASE_SETUP.md.`
  );
}

/**
 * Turns Secret Manager / project-id failures into actionable HTTPS errors
 * instead of generic INTERNAL.
 */
export function toHttpsErrorForLarpManagerCredentialSave(
  error: unknown,
  projectId: string
): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }

  const msg = error instanceof Error ? error.message : String(error);
  const grpc = grpcStatusCode(error);

  if (msg.includes("Could not resolve Google Cloud project id")) {
    return new HttpsError("failed-precondition", msg);
  }

  if (
    grpc === 7 ||
    grpc === 16 ||
    /permission|denied|secretmanager/i.test(msg)
  ) {
    return new HttpsError(
      "permission-denied",
      secretManagerSetupErrorMessage(projectId)
    );
  }

  if (/secretmanager\.googleapis\.com|Secret Manager API/i.test(msg)) {
    return new HttpsError(
      "failed-precondition",
      secretManagerSetupErrorMessage(projectId)
    );
  }

  return new HttpsError("internal", msg.slice(0, 500));
}
