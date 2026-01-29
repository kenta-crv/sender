"""Pydanticスキーマ定義.

【修正履歴】
- 2026/01/03: address に normalize_address を適用する field_validator を追加
- 2026/01/03: first_name を Optional[str] = None に変更（Geminiが返さない場合の対応）
"""

import re
from typing import Optional
from pydantic import BaseModel, Field, field_validator
from utils.formtter import normalize_company_name, normalize_tel_number, normalize_address
from utils.validator import validate_address_format, validate_company_format, validate_tel_format


class ExtractRequest(BaseModel):
    """入力."""
    customer_id: str
    company: str
    location: str
    required_businesses: list[str]
    required_genre: list[str]


class CompanyInfo(BaseModel):
    """抽出した会社情報."""

    company: str = Field(
        description=(
            "会社名。以下を満たす必要があります: \n"
            "- 『株式会社/有限会社/社会福祉/合同会社/医療法人/行政書士/一般社団法人/合資会社/法律事務所』のいずれかを含む\n"
            "- 支店・営業所・括弧（半角/全角）・スペース（半角/全角）を含まない\n"
            "- 全角英数字・記号（Ａ-Ｚａ-ｚ０-９・！-～）を含まない"
        ),
    )
    tel: Optional[str] = Field(
        default=None,
        description=(
            "電話番号。半角数字とハイフンのみで、ハイフンを含む必要があります。"
            "数字のみや括弧( ) を含む形式は不可。"
        ),
    )
    address: str = Field(description="住所。『都/道/府/県』のいずれかを含む必要があります。")
    first_name: Optional[str] = Field(
        default=None,
        description="担当者名/代表者名。肩書は含めず、苗字と名前の間には空欄をいれない",
    )
    url: Optional[str] = Field(default=None, description="公式サイトのURL")
    contact_url: Optional[str] = Field(default=None, description="問い合わせページのURL。")
    business: str = Field(description="抽出された業種。指定がある場合は特定文字列を含む必要がある。")
    genre: str = Field(description="抽出された事業内容。50文字程度で簡潔に記載。指定がある場合は特定文字列を含む必要がある。")

    # --- company ---
# --- company ---
    @field_validator("company", mode="before")
    @classmethod
    def _format_company(cls, v: str) -> str:
        return normalize_company_name(v)

    @field_validator("company", mode="after")
    @classmethod
    def _validate_company(cls, v: str) -> str:
        # 空白を許可するため、チェック用の文字列からは空白を一時的に除いて判定
        v_stripped = v.replace(" ", "").replace("　", "")
        
        if not validate_company_format(v_stripped):
            # 支店や営業所などの禁止ワードチェック（空白は除外した）
            has_forbidden = any(x in v_stripped for x in ["支店", "営業所", "（", "）", "(", ")"])
            
            # 正規表現に半角・全角スペース (\s) を追加
            relaxed_charset_ok = bool(re.fullmatch(r"[A-Za-z0-9\u3040-\u30FF\u4E00-\u9FFF\u3005\u30FC・&._\-\s]+", v))
            
            if (not has_forbidden) and relaxed_charset_ok:
                return v
            
            raise ValueError(
                "会社名の形式が不正です。主要な法人格を含み、支店・営業所・括弧を含まない必要があります。"
            )
        return v
    
    # --- tel ---
    @field_validator("tel", mode="before")
    @classmethod
    def _format_tel(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        return normalize_tel_number(v)

    @field_validator("tel", mode="after")
    @classmethod
    def _validate_tel(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        if not validate_tel_format(v):
            raise ValueError("電話番号の形式が不正です。半角数字とハイフンのみ、ハイフンを含み、数字のみ/括弧付きは不可です。")
        return v

    # --- address ---
    @field_validator("address", mode="before")
    @classmethod
    def _format_address(cls, v: str) -> str:
        return normalize_address(v)

    @field_validator("address", mode="after")
    @classmethod
    def _validate_address(cls, v: str) -> str:
        if not validate_address_format(v):
            raise ValueError("住所の形式が不正です。『都/道/府/県』のいずれかを含めてください。")
        return v

    # --- first_name ---
    @field_validator("first_name", mode="before")
    @classmethod
    def _format_first_name(cls, v) -> Optional[str]:
        if v is None:
            return None
        s = str(v).strip()
        if s == "" or s == "不明":
            return None
        s = re.sub(r"(代表取締役|取締役|社長|会長|専務|常務|理事長|院長|所長|代表)\s*", "", s)
        return s if s else None

    # --- contact_url ---
    @field_validator("contact_url", mode="before")
    @classmethod
    def _format_contact_url(cls, v) -> Optional[str]:
        if v is None:
            return None
        s = str(v).strip()
        if s == "" or s == "不明" or not s.startswith("http"):
            return None
        return s


class LLMCompanyInfo(BaseModel):
    company: Optional[str] = None
    tel: Optional[str] = None
    address: Optional[str] = None
    first_name: Optional[str] = None
    url: Optional[str] = None
    contact_url: Optional[str] = None
    business: Optional[str] = None
    genre: Optional[str] = None


class ErrorDetail(BaseModel):
    code: str
    message: str


class ExtractResponse(BaseModel):
    success: bool
    data: Optional[CompanyInfo] = None
    error: Optional[ErrorDetail] = None


class URLScore(BaseModel):
    url: str = Field(description="URL. Webコンテキストの取得に用いられた元URLか関連度の高い別ドメインURL")
    score: float = Field(description="URLと企業の関連度")


class URLScoreList(BaseModel):
    urls: list[URLScore] = Field(description="URLと企業の関連度スコア情報のリスト")
