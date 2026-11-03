/** Raw shape returned by `az carbon get-emission-report --monthly-summary`. */
export interface CarbonMonthlyRecord {
  dataType: string;
  date: string;
  carbonIntensity: number;
  latestMonthEmissions: number;
  /**
   * Day the record was last refreshed from the API (YYYY-MM-DD), set by
   * fetch_carbon_report.py (ClouDO runbook). Months that left the API window keep their old date.
   */
  retrievedAt?: string;
  /**
   * The API also returns `previousMonthEmissions`, `monthlyEmissionsChangeValue`
   * and `monthOverMonthEmissionsChangeRatio`. We deliberately do not model them:
   * Azure restates history, so those fields disagree with the adjacent row
   * Every delta here is recomputed from the emissions series.
   */
  [key: string]: unknown;
}

export interface CarbonReport {
  value: CarbonMonthlyRecord[];
}

/** One published series. Not an Azure subscription: a series may sum several. */
export interface ManifestSeries {
  slug: string;
  name: string;
  file: string;
}

export interface Manifest {
  generatedAt: string;
  emissionsUnit: string;
  carbonScope?: string;
  series: ManifestSeries[];
}
