import argparse
import storage


def main():
    parser = argparse.ArgumentParser(
        description="Arm one-time risk override for next scan result."
    )
    parser.add_argument(
        "risk_percentage",
        type=float,
        help="Next scan risk percentage override (0-30).",
    )
    parser.add_argument(
        "--note",
        default="",
        help="Optional note for audit/debug.",
    )
    args = parser.parse_args()

    storage.init_db()
    payload = storage.arm_next_risk_override(args.risk_percentage, args.note)
    print(
        f"Armed next risk override: {payload['risk_percentage']}% (one-time, note='{payload['note']}')"
    )


if __name__ == "__main__":
    main()
