#!/usr/bin/env node
/**
 * Tạo tài khoản admin bằng dòng lệnh (dùng lần đầu nếu không chạy seed.sql).
 *
 * Cách dùng:
 *   node scripts/create-admin.js admin@example.com Admin@123 "Quản trị viên"
 */
'use strict';
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const db = require('../config/db');
const { hash } = require('../utils/password');

async function main() {
  const [, , email, password, fullName = 'Admin'] = process.argv;
  if (!email || !password) {
    console.error('Cách dùng: node scripts/create-admin.js <email> <password> [fullName]');
    process.exit(1);
  }
  const passwordHash = await hash(password);
  const pool = await db.getPool();
  await db.query(
    `IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @email)
       INSERT dbo.Users (Email, PasswordHash, FullName, Role, ConsentGivenAt, ConsentVersion)
       VALUES (@email, @hash, @name, N'ADMIN', SYSUTCDATETIME(), N'v1')
     ELSE
       PRINT N'Email này đã tồn tại'`,
    { email, hash: passwordHash, name: fullName });
  console.log(`Đã tạo (hoặc đã có) tài khoản admin: ${email}`);
  await db.close();
}

main().catch((err) => { console.error(err); process.exit(1); });
