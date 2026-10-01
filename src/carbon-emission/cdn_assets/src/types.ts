/** Raw shape returned by `az carbon get-emission-report --monthly-summary`. */
export interface CarbonMonthlyRecord {
  dataType: string;
  date: string;
  carbonIntensity: number;
  latestMonthEmissions: number;
  /**
   * The API also returns `previousMonthEmissions`, `monthlyEmissionsChangeValue`
   * and `monthOverMonthEmissionsChangeRatio`. We deliberately do not model them:
   * Azure restates history, so those fields disagree with the adjacent row
   * (README §1.6). Every delta here is recomputed from the emissions series.
   */
  [key: string]: unknown;
}

export interface CarbonReport {
  value: CarbonMonthlyRecord[];
}

export interface ManifestSubscription {
  slug: string;
  name: string;
  file: string;
  subscriptionId?: string;
  /** Sample data, not a real export. Banner-flagged in the UI. */
  synthetic?: boolean;
}

export interface EquivalenceItem {
  id: string;
  label: string;
  kgCO2ePerUnit: number;
}

export interface Equivalences {
  verified: boolean;
  source: string;
  note?: string;
  items: EquivalenceItem[];
}

export interface Manifest {
  generatedAt: string;
  emissionsUnit: string;
  carbonScope?: string;
  subscriptions: ManifestSubscription[];
  equivalences?: Equivalences;
}
