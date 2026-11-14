import type { Metadata } from "next";
import "./globals.css";
import AppShell from "./components/app-shell";
export const metadata: Metadata = { title: "FacturaExpress | Facturação", description: "Gestão de facturação para empresas moçambicanas." };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="pt"><body><AppShell>{children}</AppShell></body></html>; }
