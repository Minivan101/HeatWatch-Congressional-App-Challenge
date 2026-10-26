import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {setGlobalOptions} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {loadCoolSpotsDemo} from "./demo/cool_spots_demo";
import {loadHeatGuardDemo} from "./demo/heat_guard_demo";
import {loadShadeDemo} from "./demo/shade_demo";
import {readEmulatorCoolingCenters} from "./places/emulator_centers";

setGlobalOptions({maxInstances: 10});

initializeApp();

if (process.env.FUNCTIONS_EMULATOR === "true") {
  exports.healthCheck = onCall(async () => {
    await getFirestore().collection("diagnostics").doc("latest").set({
      checkedAt: FieldValue.serverTimestamp(),
      ok: true,
    });

    return {
      message: "Flutter, Cloud Functions, and Firestore are connected.",
      ok: true,
    };
  });
  exports.getLocalCoolingCenters = onCall(async () =>
    readEmulatorCoolingCenters(getFirestore(), process.env));
  exports.getCoolSpotsDemo = onCall(async (request) => {
    try {
      return loadCoolSpotsDemo(request.data);
    } catch (error) {
      if (error instanceof RangeError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }
  });
  exports.getHeatGuardDemo = onCall(async () => loadHeatGuardDemo());
  exports.getShadeRouteDemo = onCall(async (request) => {
    try {
      return loadShadeDemo(request.data);
    } catch (error) {
      if (error instanceof RangeError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }
  });
}
