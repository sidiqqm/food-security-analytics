# Business Understanding — Global Food Security Analytics

---

## 1. Business Background

Ketahanan pangan global merupakan isu strategis yang mempengaruhi stabilitas politik, 
ekonomi, dan sosial di seluruh dunia. FAO mendefinisikan ketahanan pangan sebagai kondisi 
di mana semua orang, setiap saat, memiliki akses fisik, sosial, dan ekonomi terhadap 
pangan yang cukup, aman, dan bergizi.

Selama tiga dekade terakhir (1991–2022), produksi pangan global tumbuh signifikan, 
namun distribusinya tetap tidak merata. Negara-negara berkembang, khususnya di 
Sub-Saharan Africa dan Asia Selatan, masih menghadapi defisit pangan struktural meskipun 
secara global terjadi surplus produksi.

Project ini membangun sistem analitik terintegrasi yang menggabungkan data produksi, 
perdagangan, dan kecukupan gizi dari FAOSTAT untuk menghasilkan insight yang dapat 
mendukung pengambilan keputusan kebijakan pangan global.

---

## 2. Stakeholder

| Stakeholder | Role | Primary Need |
|---|---|---|
| FAO Director-General | Executive Decision Maker | Strategic summary, policy recommendations |
| Regional Food Security Officers | Operational Users | Regional analysis, risk identification |
| Agricultural Policy Analysts | Analytical Users | Trend analysis, correlation, forecasting |
| Member Country Representatives | Secondary Stakeholders | Country benchmarking |
| Research & Data Division | Technical Stakeholders | Methodology, reproducibility |

---

## 3. Business Problem

FAO memiliki data pertanian dan pangan dari 180+ negara selama lebih dari tiga dekade, 
namun data tersebut tersebar dalam format yang sulit dianalisis secara terintegrasi.

Pembuat kebijakan menghadapi tiga pertanyaan utama yang belum terjawab secara sistematis:

1. **Produksi:** Negara mana yang mengalami defisit produksi struktural, dan komoditas apa 
   yang paling rentan?
2. **Perdagangan:** Bagaimana ketergantungan impor pangan global berubah, dan negara mana 
   yang paling berisiko?
3. **Gizi:** Apakah kecukupan gizi global membaik, dan faktor apa yang paling 
   memengaruhinya?

---

## 4. Business Objectives

| # | Objective | Success Indicator |
|---|---|---|
| O1 | Membangun visibilitas terpadu tren produksi pangan global | Dashboard interaktif per komoditas & wilayah |
| O2 | Mengidentifikasi negara dengan ketergantungan impor tertinggi | Ranking Import Dependency Ratio |
| O3 | Menganalisis hubungan produksi vs. kecukupan gizi | Korelasi statistik signifikan |
| O4 | Proyeksi produksi komoditas strategis 2025–2027 | Forecasting dengan metode non-ML |
| O5 | Menghasilkan rekomendasi kebijakan berbasis data | ≥5 insight actionable |

---

## 5. Business Questions

### Production
1. Komoditas apa yang mengalami pertumbuhan produksi tertinggi 1991–2022?
2. Negara mana yang mendominasi produksi komoditas strategis?
3. Apakah yield per hektar meningkat sejalan dengan total produksi?

### Trade
4. Bagaimana pola net trade berubah per wilayah FAO?
5. Negara mana yang paling rentan karena ketergantungan impor?

### Food Security
6. Apakah Dietary Energy Supply (kkal/kapita/hari) membaik secara global?
7. Adakah kesenjangan signifikan antara wilayah berpenghasilan tinggi dan rendah?
8. Apa hubungan antara produksi domestik dan kecukupan gizi?

### Forecasting
9. Proyeksi produksi komoditas utama untuk 2025–2027?

---

## 6. KPI Definition

| KPI | Definition | Unit | Source |
|---|---|---|---|
| Total Production Volume | Agregat produksi per tahun | Metric Ton | FAOSTAT Production |
| Production CAGR (10Y) | Compound Annual Growth Rate | % / year | Calculated |
| Net Trade Balance | Ekspor – Impor | 1000 USD | FAOSTAT Trade |
| Import Dependency Ratio | Import / (Production + Import – Export) × 100 | % | Calculated |
| Dietary Energy Supply | Ketersediaan kalori per kapita per hari | kcal/cap/day | FAOSTAT Food Balance |
| Crop Yield | Produksi per satuan lahan panen | kg/ha | FAOSTAT Production |
| YoY Production Growth | Pertumbuhan produksi tahunan | % | Calculated |

---

## 7. Success Metrics

| Dimension | Criteria |
|---|---|
| Completeness | Seluruh 15 komponen wajib selesai |
| Data Coverage | ≥50 negara, ≥10 komoditas, 1991–2022 |
| Dashboard Usability | Dapat dibaca stakeholder non-teknis |
| Statistical Rigor | Setiap test disertai interpretasi bisnis |
| Reproducibility | Seluruh transformasi via dbt |
| Documentation | README cukup untuk replikasi |

---

## 8. Scope

### In Scope
- Produksi pertanian (crops, livestock secondary)
- Perdagangan internasional (ekspor & impor)
- Food supply / dietary adequacy
- Analisis negara dan regional (FAO regions)
- Periode 1991–2022

### Out of Scope
- Harga real-time atau sub-tahunan
- Analisis rantai pasok mikro
- Machine learning / complex forecasting
- Data cuaca / iklim
- Kebijakan subsidi per negara

---

## 9. Assumptions

| # | Assumption | Justification |
|---|---|---|
| A1 | Data Flag "A" dianggap akurat | FAO adalah sumber paling otoritatif |
| A2 | Data Flag "E" digunakan namun ditandai | Metodologi estimasi standar internasional |
| A3 | Agregasi regional merupakan turunan negara anggota | Sesuai metodologi FAO |
| A4 | Satuan ton = metric ton (1.000 kg) | Standar FAOSTAT |
| A5 | Nilai perdagangan dalam USD nominal | Fokus pada volume, bukan nilai riil |
| A6 | Perubahan definisi negara ditangani di staging | Dicatat dalam data dictionary |

---

## 10. Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Data tidak tersedia negara tertentu | Tinggi | Sedang | Dokumentasi missing pattern |
| Perubahan metodologi FAO | Sedang | Tinggi | Periksa metadata; catat dalam dokumentasi |
| Inkonsistensi satuan antar dataset | Sedang | Tinggi | Standardisasi di dbt staging |
| Over-interpretation data estimasi | Sedang | Tinggi | Selalu sertakan caveat |
| Double-count agregat regional | Tinggi | Tinggi | Filter eksplisit di staging |
