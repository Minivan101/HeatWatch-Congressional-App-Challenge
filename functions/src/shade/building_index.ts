import {MetricPoint} from "./geometry";
import {MAX_SHADOW_LENGTH_METERS} from "./shadows";

export class BuildingIndex {
  private readonly cells = new Map<string, number[]>();
  private readonly large: number[] = [];
  private readonly cellMeters = 100;

  constructor(footprints: MetricPoint[][]) {
    footprints.forEach((ring, index) => {
      const east = ring.map((p) => p.eastMeters);
      const north = ring.map((p) => p.northMeters);
      const left = Math.floor((Math.min(...east) -
        MAX_SHADOW_LENGTH_METERS) / this.cellMeters);
      const right = Math.floor((Math.max(...east) +
        MAX_SHADOW_LENGTH_METERS) / this.cellMeters);
      const bottom = Math.floor((Math.min(...north) -
        MAX_SHADOW_LENGTH_METERS) / this.cellMeters);
      const top = Math.floor((Math.max(...north) +
        MAX_SHADOW_LENGTH_METERS) / this.cellMeters);
      if ((right - left + 1) * (top - bottom + 1) > 400) {
        this.large.push(index);
        return;
      }
      for (let x = left; x <= right; x++) {
        for (let y = bottom; y <= top; y++) {
          const key = `${x}_${y}`;
          const members = this.cells.get(key) ?? [];
          members.push(index);
          this.cells.set(key, members);
        }
      }
    });
  }

  candidates(point: MetricPoint): number[] {
    const x = Math.floor(point.eastMeters / this.cellMeters);
    const y = Math.floor(point.northMeters / this.cellMeters);
    return [...this.large, ...(this.cells.get(`${x}_${y}`) ?? [])];
  }
}
