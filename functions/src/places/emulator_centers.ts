import {Firestore} from "firebase-admin/firestore";
import {parseCuratedCenterDataset} from "./curated_centers";
import {centerDateStatus, localCalendarDate} from "./local_date";

const DATASET_ID = "clark-county-june-2026-archived";

export async function readEmulatorCoolingCenters(
  db: Firestore, env: NodeJS.ProcessEnv, now = new Date(),
): Promise<Record<string, unknown>> {
  if (env.FUNCTIONS_EMULATOR !== "true" ||
    !["127.0.0.1:8080", "localhost:8080"].includes(
      env.FIRESTORE_EMULATOR_HOST ?? "") ||
    (env.GCLOUD_PROJECT !== undefined &&
      env.GCLOUD_PROJECT !== "heatwatch-nv")) {
    throw new RangeError("Local Firestore emulator is required.");
  }
  const root = db.collection("coolingCenterDatasets").doc(DATASET_ID);
  const [header, records] = await Promise.all([
    root.get(), root.collection("centers").get(),
  ]);
  if (!header.exists || records.empty ||
    header.data()?.centerCount !== records.size) {
    throw new RangeError("Saved local center records are missing.");
  }
  const metadata = {...header.data()};
  delete metadata.centerCount;
  const dataset = parseCuratedCenterDataset({
    ...metadata,
    centers: records.docs.map((record) => ({...record.data(), id: record.id})),
  });
  if (dataset.datasetId !== DATASET_ID) {
    throw new RangeError("Wrong local center dataset.");
  }
  const localDate = localCalendarDate(now, dataset.timeZoneId);
  return {
    source: "LOCAL_FIRESTORE_EMULATOR",
    dataset,
    localDate,
    dateStatuses: Object.fromEntries(dataset.centers.map((center) => [
      center.id,
      centerDateStatus(center.validFrom, center.validUntil, localDate),
    ])),
  };
}
