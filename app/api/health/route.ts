"use client";
import { NextResponse } from "next/server";

// Health endpoint deliberately reports application readiness only, not fiscal certification.
export async function GET() {
  return NextResponse.json({ name: "FacturaExpress", status: "development", fiscalCertification: "not_verified", database: "not_connected", timestamp: new Date().toISOString() });
}
