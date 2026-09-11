import argparse
import storage


def main():
    parser = argparse.ArgumentParser(
        description="Arm one-time risk override for next scan result."
    )
    parser.add_argument(
        "risk_percentage",
        nargs="?",
        type=float,
        help="Next scan risk percentage override (0-30).",
    )
    parser.add_argument(
        "--note",
        default="",
        help="Optional note for audit/debug.",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Show whether the next analyze call is armed.",
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Clear a previously armed override.",
    )
    args = parser.parse_args()

    storage.init_db()

    if args.status:
        payload = storage.peek_next_risk_override()
        if payload is None:
            print("Override is NOT armed. Next scan will use normal AI scoring.")
        else:
            print(
                f"Override IS armed: {payload.get('risk_percentage')}% "
                f"(note='{payload.get('note', '')}'). "
                "Gemini will be skipped on the next /api/v1/analyze."
            )
        return

    if args.clear:
        cleared = storage.clear_next_risk_override()
        print("Cleared armed override." if cleared else "No override was armed.")
        return

    if args.risk_percentage is None:
        parser.error("risk_percentage is required unless using --status or --clear")

    payload = storage.arm_next_risk_override(args.risk_percentage, args.note)
    print(
        f"Armed next risk override: {payload['risk_percentage']}% "
        f"(one-time, note='{payload['note']}'). "
        "The next /api/v1/analyze will skip Gemini and return this score immediately."
    )


if __name__ == "__main__":
    main()
