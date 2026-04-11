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
OUTPUT_DIR = f"/Volumes/{CATALOG}/{SCHEMA}/{VOLUME}/viewing_sessions"
OUTPUT_FILE = f"viewing_sessions_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
NUM_ROWS = 72

BASE_START = datetime(2026, 4, 8, 0, 0, 0)
BASE_END = datetime(2026, 4, 9, 12, 0, 0)

random.seed(42)


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


def weighted_choice(items, weights):
    return random.choices(items, weights=weights, k=1)[0]


def random_timestamp(start: datetime, end: datetime, preferred_evening=True) -> datetime:
    delta_seconds = int((end - start).total_seconds())

    if preferred_evening and random.random() < 0.6:
        # Bias more sessions toward evening hours
        day_offset = random.randint(0, max((end.date() - start.date()).days, 0))
        chosen_day = start.date() + timedelta(days=day_offset)
        hour = weighted_choice(
            [7, 8, 9, 12, 13, 18, 19, 20, 21, 22, 23],
            [1, 1, 1, 1, 1, 3, 5, 6, 6, 4, 2]
        )
        minute = random.randint(0, 59)
        second = random.randint(0, 59)
        ts = datetime.combine(chosen_day, datetime.min.time()).replace(
            hour=hour, minute=minute, second=second
        )
        if ts < start:
            return start
        if ts > end:
            return end - timedelta(minutes=1)
        return ts

    random_seconds = random.randint(0, delta_seconds)
    return start + timedelta(seconds=random_seconds)


def build_user_genre_preferences(users_df: pd.DataFrame, genres_df: pd.DataFrame):
    genre_ids = genres_df["genre_id"].tolist()
    preferences = {}

    for _, row in users_df.iterrows():
        preferred = row.get("preferred_genre_id", None)

        if pd.notna(preferred) and preferred in genre_ids:
            weights = {g: 1 for g in genre_ids}
            weights[preferred] = 5
        else:
            fav = random.choice(genre_ids)
            weights = {g: 1 for g in genre_ids}
            weights[fav] = 4

        preferences[row["user_id"]] = weights

    return preferences


def pick_content_for_user(user_id, content_df, user_genre_preferences):
    genre_weights = user_genre_preferences[user_id]
    eligible = content_df.copy()
    eligible["genre_weight"] = eligible["genre_id"].map(genre_weights).fillna(1)

    sampled_row = eligible.sample(
        n=1,
        weights=eligible["genre_weight"],
        replace=True,
        random_state=random.randint(1, 999999)
    ).iloc[0]

    return sampled_row


def realistic_watch_minutes(duration_minutes: int, device_type: str, content_type: str):
    base_completion = {
        "movie": random.uniform(0.35, 0.95),
        "series": random.uniform(0.40, 1.00),
        "live": random.uniform(0.25, 0.90),
        "documentary": random.uniform(0.30, 0.85),
    }.get(content_type, random.uniform(0.30, 0.90))

    # Device effect
    if device_type == "smart_tv":
        base_completion *= random.uniform(1.00, 1.15)
    elif device_type == "mobile":
        base_completion *= random.uniform(0.65, 0.95)
    elif device_type == "tablet":
        base_completion *= random.uniform(0.75, 1.00)
    else:
        base_completion *= random.uniform(0.80, 1.00)

    base_completion = min(max(base_completion, 0.05), 1.0)
    watch_minutes = max(3, round(duration_minutes * base_completion))

    return watch_minutes, round(base_completion * 100, 2)


# ----------------------------
# Main generator
# ----------------------------
def main():
    ensure_output_dir(OUTPUT_DIR)

    users_df = load_csv("users_seed.csv")
    devices_df = load_csv("devices.csv")
    genres_df = load_csv("genres.csv")
    content_df = load_csv("content_catalog.csv")

    # Basic validation
    required_user_cols = {"user_id"}
    required_device_cols = {"device_id", "device_type"}
    required_content_cols = {"content_id", "genre_id", "content_type", "duration_minutes"}

    if not required_user_cols.issubset(users_df.columns):
        raise ValueError(f"users_seed.csv must contain columns: {required_user_cols}")

    if not required_device_cols.issubset(devices_df.columns):
        raise ValueError(f"devices.csv must contain columns: {required_device_cols}")

    if not required_content_cols.issubset(content_df.columns):
        raise ValueError(f"content_catalog.csv must contain columns: {required_content_cols}")

    user_genre_preferences = build_user_genre_preferences(users_df, genres_df)

    records = []

    for _ in range(NUM_ROWS):
        user_row = users_df.sample(n=1, random_state=random.randint(1, 999999)).iloc[0]

        # Prefer user's preferred device type if available
        preferred_device_type = user_row.get("preferred_device_type", None)
        if pd.notna(preferred_device_type) and preferred_device_type in devices_df["device_type"].values:
            device_pool = devices_df[devices_df["device_type"] == preferred_device_type]
            if device_pool.empty:
                device_pool = devices_df
        else:
            device_pool = devices_df

        device_row = device_pool.sample(n=1, random_state=random.randint(1, 999999)).iloc[0]
        content_row = pick_content_for_user(user_row["user_id"], content_df, user_genre_preferences)

        start_ts = random_timestamp(BASE_START, BASE_END, preferred_evening=True)

        duration_minutes = int(content_row["duration_minutes"])
        watch_minutes, completion_pct = realistic_watch_minutes(
            duration_minutes=duration_minutes,
            device_type=device_row["device_type"],
            content_type=content_row["content_type"]
        )

        end_ts = start_ts + timedelta(minutes=watch_minutes)

        record = {
            "session_id": f"S-{uuid.uuid4().hex[:12].upper()}",
            "user_id": user_row["user_id"],
            "device_id": device_row["device_id"],
            "content_id": content_row["content_id"],
            "session_start_ts": start_ts.isoformat(),
            "session_end_ts": end_ts.isoformat(),
            "watch_minutes": watch_minutes,
            "completion_pct": completion_pct,
            "autoplay_flag": random.random() < 0.25,
            "is_logged_in": True,
            "country_code": user_row.get("country_code", "FI"),
            "session_date": start_ts.date().isoformat(),
            "ingestion_ts": BASE_END.isoformat(),
            "source_file": OUTPUT_FILE,
        }

        records.append(record)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)

    pd.DataFrame(records).to_json(
        output_path,
        orient="records",
        lines=False,
        indent=2
    )

    print(f"Generated {len(records)} viewing session rows -> {output_path}")


if __name__ == "__main__":
    main()
