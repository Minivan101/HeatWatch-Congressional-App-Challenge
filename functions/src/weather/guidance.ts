
export type UvGuidance = {
  category: "low" | "moderate-to-high" | "very-high-to-extreme";
  message: string;
};

export function uvGuidance(uv: number): UvGuidance {
  if (!Number.isFinite(uv) || uv < 0) {
    throw new RangeError("UV Index must be a nonnegative finite number.");
  }
  if (uv < 3) {
    return {
      category: "low",
      message: "UV exposure is low. Minimal sun protection is generally " +
        "needed.",
    };
  }
  if (uv < 8) {
    return {
      category: "moderate-to-high",
      message: "Seek shade when practical. Use broad-spectrum sunscreen, " +
        "protective clothing, a hat, and sunglasses.",
    };
  }
  return {
    category: "very-high-to-extreme",
    message: "Use extra sun protection. Seek shade and wear broad-spectrum " +
      "sunscreen, protective clothing, a hat, and sunglasses.",
  };
}
