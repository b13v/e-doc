# curl commands for testing

Replace ALL CAPS placeholders.

## 1) Signup (get token)
```bash
TOKEN=$(curl -X POST "http://localhost:4000/v1/auth/signup" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "USER_EMAIL",
    "password": "USER_PASSWORD"
  }' | jq -r .access_token)
echo "$TOKEN"
```

## 2) Login (get token)
```bash
curl -X POST "http://localhost:4000/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "USER_EMAIL",
    "password": "USER_PASSWORD"
  }'
```

## 3) List banks (get `BANK_ID`)
```bash
curl -X GET "http://localhost:4000/v1/dicts/banks" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## 4) List KBE codes (get `KBE_ID`)
```bash
curl -X GET "http://localhost:4000/v1/dicts/kbe" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## 5) List KNP codes (get `KNP_ID`)
```bash
curl -X GET "http://localhost:4000/v1/dicts/knp" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## 6) Upsert company (required before invoices)
```bash
curl -X PUT "http://localhost:4000/v1/company" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme LLC",
    "legal_form": "LLC",
    "bin_iin": "123456789012",
    "city": "Almaty",
    "address": "Some Street 1",
    "bank_name": "ForteBank",
    "bank_id": "BANK_ID",
    "kbe_code_id": "KBE_ID",
    "knp_code_id": "KNP_ID",
    "iban": "KZ123456789012345678",
    "phone": "+7 (777) 123 45 67",
    "representative_name": "John Doe",
    "representative_title": "Director",
    "basis": "Charter",
    "email": "info@example.com"
  }'
```

## 7) Create company bank account
```bash
curl -X POST "http://localhost:4000/v1/company/bank-accounts" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "Main account",
    "iban": "KZ123456789012345678",
    "bank_id": "BANK_ID",
    "kbe_code_id": "KBE_ID",
    "knp_code_id": "KNP_ID",
    "is_default": true
  }'
```

## 8) List company bank accounts (get `BANK_ACCOUNT_ID`)
```bash
curl -X GET "http://localhost:4000/v1/company/bank-accounts" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## 9) Create invoice (with bank account selection)
```bash
curl -X POST "http://localhost:4000/v1/invoices" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "service_name": "Consulting",
    "issue_date": "2026-01-15",
    "currency": "KZT",
    "buyer_name": "Buyer LLC",
    "buyer_bin_iin": "123456789012",
    "buyer_address": "Almaty, Abay Ave 10",
    "vat_rate": 0,
    "bank_account_id": "BANK_ACCOUNT_ID",
    "kbe_code_id": "KBE_ID",
    "knp_code_id": "KNP_ID",
    "items": [
      {"name": "Service A", "qty": 2, "unit_price": "1000.00"}
    ]
  }'
```

## 10) Issue invoice
```bash
curl -X POST "http://localhost:4000/v1/invoices/INVOICE_ID/issue" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## 11) Download PDF
```bash
curl -X GET "http://localhost:4000/v1/invoices/INVOICE_ID/pdf" \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -o invoice.pdf
```
