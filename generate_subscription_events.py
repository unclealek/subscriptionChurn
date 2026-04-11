import os
import uuid
import random
from datetime import datetime, timedelta
import pandas as pd


# ----------------------------
# Config
# ----------------------------
# Use environment variables so the same script can run in dev and prod jobs.
SEED_DIR = os.getenv("SEED_DIR", "/Workspace/Users/kelvin.aliche@gmail.com/transformation/seeds")
CATALOG = os.getenv("VOLUME_CATALOG", "transform")
SCHEMA = os.getenv("VOLUME_SCHEMA", "movierecommendation")
VOLUME = os.getenv("VOLUME_NAME", "raw_data")
OUTPUT_DIR = f"/Volumes/{CATALOG}/{SCHEMA}/{VOLUME}/subscription_events"
OUTPUT_FILE = f"subscription_events_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
NUM_ROWS = 32

BASE_START = datetime(2026, 4, 8, 0, 0, 0)
BASE_END = datetime(2026, 4, 9, 12, 0, 0, 0)

random.seed(99)


# ----------------------------
# Helpers
# ----------------------------
def ensure_output_dir(path: str):
    """Create directory in Volume if it doesn't exist"""
    if path.startswith("/Volumes/"):
        # Use dbutils for Volume paths
        try:
            dbutils.fs.mkdirs(path)
        except Exception as e:
            print(f"Directory may already exist or error creating: {e}")
    else:
        os.makedirs(path, exist_ok=True)


def load_csv(filename: str) -> pd.DataFrame:
    path = os.path.join(SEED_DIR, filename)
    return pd.read_csv(path)


def random_timestamp(start: datetime, end: datetime) -> datetime:
    delta_seconds = int((end - start).total_seconds())
    return start + timedelta(seconds=random.randint(0, delta_seconds))


def get_plan_price(plan_id: str, plans_df: pd.DataFrame) -> float:
    row = plans_df.loc[plans_df["plan_id"] == plan_id]
    if row.empty:
        return 0.0
    return float(row.iloc[0].get("monthly_price", 0.0))


def choose_plan(plans_df: pd.DataFrame, preferred_tiers=None):
    df = plans_df.copy()
    if preferred_tiers and "plan_tier" in df.columns:
        filtered = df[df["plan_tier"].isin(preferred_tiers)]
        if not filtered.empty:
            df = filtered
    return df.sample(n=1, random_state=random.randint(1, 999999)).iloc[0]


def plan_status_from_tier(plan_tier: str) -> str:
    if plan_tier == "free":
        return "free"
    if plan_tier == "trial":
        return "trial"
    return "premium"


def create_transition(user_row, plans_df):
    initial_plan_id = user_row.get("initial_plan_id", None)
    initial_status = str(user_row.get("initial_subscription_status", "free")).lower()

    transition_type = random.choices(
        population=["trial_start", "subscribe", "upgrade", "downgrade", "renew", "cancel"],
        weights=[4, 6, 3, 2, 7, 5],
        k=1
    )[0]

    # Default values
    old_plan_id = initial_plan_id
    new_plan_id = initial_plan_id
    old_status = initial_status
    new_status = initial_status

    if transition_type == "trial_start":
        trial_plan = choose_plan(plans_df, preferred_tiers=["trial"]) if "plan_tier" in plans_df.columns else choose_plan(plans_df)
        old_status = "free"
        old_plan_id = initial_plan_id if pd.notna(initial_plan_id) else None
        new_plan_id = trial_plan["plan_id"]
        new_status = "trial"

    elif transition_type == "subscribe":
        paid_plan = choose_plan(plans_df, preferred_tiers=["standard", "premium"]) if "plan_tier" in plans_df.columns else choose_plan(plans_df)
        old_status = initial_status
        old_plan_id = initial_plan_id
        new_plan_id = paid_plan["plan_id"]
        new_status = "premium"

    elif transition_type == "upgrade":
        paid_plan = choose_plan(plans_df, preferred_tiers=["premium"]) if "plan_tier" in plans_df.columns else choose_plan(plans_df)
        old_status = "premium" if initial_status in ["premium", "trial"] else "free"
        new_status = "premium"
        old_plan_id = initial_plan_id
        new_plan_id = paid_plan["plan_id"]

    elif transition_type == "downgrade":
        std_plan = choose_plan(plans_df, preferred_tiers=["standard", "free"]) if "plan_tier" in plans_df.columns else choose_plan(plans_df)
        old_status = "premium"
        old_plan_id = initial_plan_id
        new_plan_id = std_plan["plan_id"]
        new_status = plan_status_from_tier(std_plan.get("plan_tier", "free"))

    elif transition_type == "renew":
        if pd.isna(initial_plan_id):
            paid_plan = choose_plan(plans_df, preferred_tiers=["standard", "premium"]) if "plan_tier" in plans_df.columns else choose_plan(plans_df)
            old_plan_id = paid_plan["plan_id"]
            new_plan_id = paid_plan["plan_id"]
        else:
            old_plan_id = initial_plan_id
            new_plan_id = initial_plan_id
        old_status = "premium" if initial_status != "free" else "premium"
        new_status = "premium"

    elif transition_type == "cancel":
        old_plan_id = initial_plan_id
        new_plan_id = initial_plan_id
        old_status = "premium" if initial_status in ["premium", "trial"] else "premium"
        new_status = "cancelled"

    price = get_plan_price(new_plan_id, plans_df) if pd.notna(new_plan_id) else 0.0

    return {
        "event_type": transition_type,
        "old_plan_id": old_plan_id,
        "new_plan_id": new_plan_id,
        "old_status": old_status,
        "new_status": new_status,
        "price": round(price, 2),
    }


# ----------------------------
# Main generator
# ----------------------------
def main():
    ensure_output_dir(OUTPUT_DIR)

    users_df = load_csv("users_seed.csv")
    plans_df = load_csv("subscription_plans.csv")

    required_user_cols = {"user_id"}
    required_plan_cols = {"plan_id"}

    if not required_user_cols.issubset(users_df.columns):
        raise ValueError(f"users_seed.csv must contain columns: {required_user_cols}")

    if not required_plan_cols.issubset(plans_df.columns):
        raise ValueError(f"subscription_plans.csv must contain columns: {required_plan_cols}")

    records = []

    for _ in range(NUM_ROWS):
        user_row = users_df.sample(n=1, random_state=random.randint(1, 999999)).iloc[0]
        ts = random_timestamp(BASE_START, BASE_END)

        transition = create_transition(user_row, plans_df)

        record = {
            "subscription_event_id": f"SE-{uuid.uuid4().hex[:12].upper()}",
            "user_id": user_row["user_id"],
            "event_type": transition["event_type"],
            "old_plan_id": transition["old_plan_id"],
            "new_plan_id": transition["new_plan_id"],
            "old_status": transition["old_status"],
            "new_status": transition["new_status"],
            "event_ts": ts.isoformat(),
            "price": transition["price"],
            "currency": "EUR",
            "offer_code": random.choice(["SPRING10", "WELCOME7", "NONE", "NONE", "NONE"]),
            "source_file": OUTPUT_FILE,
            "ingestion_ts": BASE_END.isoformat(),
        }

        records.append(record)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)

    pd.DataFrame(records).to_json(
        output_path,
        orient="records",
        lines=False,
        indent=2
    )

    print(f"Generated {len(records)} subscription event rows -> {output_path}")


if __name__ == "__main__":
    main()
