BEGIN;

  WITH target_user AS (
    SELECT id
    FROM users
    WHERE lower(email) = lower('zabkeeva@mail.ru')
      AND verified_at IS NOT NULL
  ),
  blocked AS (
    SELECT
      (SELECT count(*) FROM companies c WHERE c.user_id IN (SELECT id FROM target_user)) AS companies_count,
      (SELECT count(*) FROM tenant_memberships tm WHERE tm.user_id IN (SELECT id FROM target_user)) AS memberships_count
  ),
  deletable_user AS (
    SELECT id
    FROM target_user
    WHERE (
      SELECT companies_count + memberships_count
      FROM blocked
    ) = 0
  )
  DELETE FROM refresh_tokens
  WHERE user_id IN (SELECT id FROM deletable_user);

  DELETE FROM email_verification_tokens
  WHERE user_id IN (
    SELECT id
    FROM users
    WHERE lower(email) = lower('zabkeeva@mail.ru')
      AND verified_at IS NOT NULL
      AND id NOT IN (
        SELECT c.user_id FROM companies c WHERE c.user_id IS NOT NULL
        UNION
        SELECT tm.user_id FROM tenant_memberships tm WHERE tm.user_id IS NOT NULL
      )
  );

  DELETE FROM users
  WHERE id IN (
    SELECT id
    FROM users
    WHERE lower(email) = lower('zabkeeva@mail.ru')
      AND verified_at IS NOT NULL
      AND id NOT IN (
        SELECT c.user_id FROM companies c WHERE c.user_id IS NOT NULL
        UNION
        SELECT tm.user_id FROM tenant_memberships tm WHERE tm.user_id IS NOT NULL
      )
  );

  COMMIT;