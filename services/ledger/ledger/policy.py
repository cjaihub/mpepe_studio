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
Fiat accounts carry the currency in the name (fees_usd holds USD):
  sys:payout_source_{cur}    cash value of Diamonds converted for a payout (<= 0)
  sys:payout_clearing_{cur}  net payout owed to the creator until the partner settles it
  sys:fees_{cur}             Oneova's fee revenue
  sys:biz_inflow_{cur}       buyers' card payments for Biz orders (<= 0)
  sys:biz_escrow_{cur}       Biz order money held until delivery
  u:{uid}:biz_payable_{cur}  what Oneova owes a seller or rider for an order
  p:{partner}:share_{cur}    a partner's revenue share of fees
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
FIAT_USER = {"biz_payable"}
FIAT_SYSTEM = {"payout_source", "payout_clearing", "fees", "biz_inflow", "biz_escrow"}
FIAT_PARTNER = {"share"}
FIAT_NEGATIVE_OK = {"payout_source", "biz_inflow"}
_FIAT = re.compile(r"^([a-z_]+)_([a-z]{3})$")
_PARTNER = re.compile(r"^[a-z0-9_]{2,32}$")


def fiat_parts(suffix: str) -> tuple[str, str] | None:
    """'fees_usd' -> ('fees', 'USD')."""
    m = _FIAT.match(suffix)
    return (m.group(1), m.group(2).upper()) if m else None

_ID = re.compile(r"^(u|sys|p):[A-Za-z0-9_-]{1,128}(:[a-z_]{1,32})?$")


class AccountError(ValueError):
    pass


def validate_account_id(account: str) -> None:
    if not isinstance(account, str) or not _ID.match(account):
        raise AccountError(f"bad account id: {account!r}")
    parts = account.split(":")
    if parts[0] == "u" and (len(parts) != 3 or (parts[2] not in USER_ACCOUNTS and (fiat_parts(parts[2]) or ("", ""))[0] not in FIAT_USER)):
        raise AccountError(f"unknown user account: {account}")
    if parts[0] == "sys" and (len(parts) != 2 or (parts[1] not in SYSTEM_ACCOUNTS and (fiat_parts(parts[1]) or ("", ""))[0] not in FIAT_SYSTEM)):
        raise AccountError(f"unknown system account: {account}")
    if parts[0] == "p" and (len(parts) != 3 or not _PARTNER.match(parts[1]) or (fiat_parts(parts[2]) or ("", ""))[0] not in FIAT_PARTNER):
        raise AccountError(f"unknown partner account: {account}")


def account_currency_ok(account: str, currency: str) -> bool:
    parts = account.split(":")
    name = parts[-1]
    fixed = USER_ACCOUNTS.get(name) if parts[0] == "u" else SYSTEM_ACCOUNTS.get(name) if parts[0] == "sys" else None
    if fixed:
        return fixed == currency
    fiat = fiat_parts(name)
    return bool(fiat) and fiat[1] == currency and currency not in ("XCN", "XDM")


def allow_negative(account: str) -> bool:
    if account in NEGATIVE_OK or account.endswith(":coin_debt"):
        return True
    fiat = fiat_parts(account.split(":")[-1])
    return account.startswith("sys:") and bool(fiat) and fiat[0] in FIAT_NEGATIVE_OK


def fiat(scope: str, kind: str, currency: str, who: str | None = None) -> str:
    """fiat('sys', 'fees', 'USD') -> 'sys:fees_usd'; fiat('p', 'share', 'USD', 'flutterwave')."""
    acc = f"{scope}:{who}:{kind}_{currency.lower()}" if who else f"{scope}:{kind}_{currency.lower()}"
    validate_account_id(acc)
    return acc


def user(uid: str, kind: str) -> str:
    acc = f"u:{uid}:{kind}"
    validate_account_id(acc)
    return acc
