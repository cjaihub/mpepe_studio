"""Which accounts may exist, in which currency, and which may go negative.

Account ids:
  u:{uid}:coins          XCN  coins a user bought on Play
  u:{uid}:coin_debt      XCN  coins owed after a refunded pack (<= 0)
  u:{uid}:dm_pending     XDM  Diamonds earned, in the hold period
  u:{uid}:dm_available   XDM  Diamonds that can be withdrawn
  u:{uid}:dm_locked      XDM  Diamonds inside an open withdrawal
  sys:coins_issued       XCN  source of all coins sold (negative = coins out there)
  sys:coins_spent        XCN  coins spent on gifts (platform's side of a gift)
  sys:dm_issued          XDM  source of all Diamonds (negative = Diamonds out there)
  sys:dm_paid_out        XDM  Diamonds that left as a payout
  p:{partner}:...        reserved for Phase 3 partner accounts
"""
from __future__ import annotations

import re

USER_ACCOUNTS: dict[str, str] = {
    "coins": "XCN",
    "coin_debt": "XCN",
    "dm_pending": "XDM",
    "dm_available": "XDM",
    "dm_locked": "XDM",
}
SYSTEM_ACCOUNTS: dict[str, str] = {
    "coins_issued": "XCN",
    "coins_spent": "XCN",
    "dm_issued": "XDM",
    "dm_paid_out": "XDM",
}
# Sources (the other side of everything issued) and debts are the only accounts below zero.
NEGATIVE_OK = {"sys:coins_issued", "sys:dm_issued"}

_ID = re.compile(r"^(u|sys|p):[A-Za-z0-9_-]{1,128}(:[a-z_]{1,32})?$")


class AccountError(ValueError):
    pass


def validate_account_id(account: str) -> None:
    if not isinstance(account, str) or not _ID.match(account):
        raise AccountError(f"bad account id: {account!r}")
    parts = account.split(":")
    if parts[0] == "u" and (len(parts) != 3 or parts[2] not in USER_ACCOUNTS):
        raise AccountError(f"unknown user account: {account}")
    if parts[0] == "sys" and (len(parts) != 2 or parts[1] not in SYSTEM_ACCOUNTS):
        raise AccountError(f"unknown system account: {account}")
    if parts[0] == "p":
        raise AccountError("partner accounts arrive in Phase 3")


def account_currency_ok(account: str, currency: str) -> bool:
    parts = account.split(":")
    if parts[0] == "u":
        return USER_ACCOUNTS.get(parts[2]) == currency
    if parts[0] == "sys":
        return SYSTEM_ACCOUNTS.get(parts[1]) == currency
    return False


def allow_negative(account: str) -> bool:
    return account in NEGATIVE_OK or account.endswith(":coin_debt")


def user(uid: str, kind: str) -> str:
    acc = f"u:{uid}:{kind}"
    validate_account_id(acc)
    return acc
