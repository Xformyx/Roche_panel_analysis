/**
 * Gene Expression Viewer Presets
 * Categorized gene sets for quick selection in the RNA-seq analysis UI.
 * Organized by: Cancer Types, Signaling Pathways, Cellular Functions,
 *               Epigenetics, Metabolism, Clinical Biomarkers, Roche/KAPA Panels
 */

const GENE_PRESETS = {

  // ── 1. Cancer Types (암종별) ─────────────────────────────────────────────
  "Cancer Types (암종별)": [
    {
      label: "Breast Cancer (유방암)",
      genes: "BRCA1,BRCA2,ERBB2,ESR1,PGR,PIK3CA,PTEN,TP53,AKT1,CDH1,CCND1,MYC,GATA3"
    },
    {
      label: "Lung Cancer NSCLC (폐암)",
      genes: "EGFR,KRAS,ALK,ROS1,MET,BRAF,RET,NTRK1,ERBB2,TP53,STK11,KEAP1,NF1"
    },
    {
      label: "Lung Cancer SCLC (소세포폐암)",
      genes: "TP53,RB1,CREBBP,EP300,MYC,MYCL,MYCN,PTEN,SOX2,NOTCH1"
    },
    {
      label: "Colorectal Cancer (대장암)",
      genes: "APC,KRAS,TP53,SMAD4,PIK3CA,BRAF,NRAS,CTNNB1,PTEN,MLH1,MSH2,MSH6"
    },
    {
      label: "Gastric Cancer (위암)",
      genes: "TP53,KRAS,PIK3CA,ERBB2,ARID1A,CDH1,CTNNB1,RHOA,SMAD4,FGFR2"
    },
    {
      label: "Hepatocellular Carcinoma (간암)",
      genes: "TP53,CTNNB1,TERT,AXIN1,ARID1A,RB1,PTEN,PIK3CA,KEAP1,NFE2L2"
    },
    {
      label: "Pancreatic Cancer (췌장암)",
      genes: "KRAS,TP53,SMAD4,CDKN2A,ARID1A,BRCA2,GNAS,RNF43,TGFBR2,MLL3"
    },
    {
      label: "Prostate Cancer (전립선암)",
      genes: "AR,PTEN,TP53,RB1,MYC,TMPRSS2,ERG,FOXA1,SPOP,CDK12,BRCA2"
    },
    {
      label: "Melanoma (흑색종)",
      genes: "BRAF,NRAS,KIT,PTEN,TP53,CDKN2A,MAP2K1,NF1,RAC1,GNAQ,GNA11"
    },
    {
      label: "Ovarian Cancer (난소암)",
      genes: "BRCA1,BRCA2,TP53,PTEN,PIK3CA,KRAS,BRAF,NRAS,CDK12,RB1"
    },
    {
      label: "Bladder Cancer (방광암)",
      genes: "TP53,FGFR3,PIK3CA,RB1,CDKN2A,ERBB2,ERBB3,ARID1A,KDM6A,TSC1"
    },
    {
      label: "Thyroid Cancer (갑상선암)",
      genes: "BRAF,RAS,RET,TERT,PIK3CA,PTEN,AKT1,TP53,CTNNB1,DICER1"
    },
    {
      label: "Lymphoma / Leukemia (혈액암)",
      genes: "BCL2,MYC,BCL6,CCND1,TP53,PTEN,NOTCH1,DNMT3A,TET2,IDH1,IDH2,FLT3"
    },
    {
      label: "Glioblastoma (교모세포종)",
      genes: "EGFR,PTEN,TP53,RB1,IDH1,IDH2,ATRX,TERT,CDKN2A,NF1,PIK3CA"
    }
  ],

  // ── 2. Signaling Pathways (신호전달 경로별) ──────────────────────────────
  "Signaling Pathways (신호전달)": [
    {
      label: "PI3K/AKT/mTOR",
      genes: "PIK3CA,PIK3R1,PTEN,AKT1,AKT2,AKT3,MTOR,TSC1,TSC2,RICTOR,RPTOR"
    },
    {
      label: "MAPK/ERK (RAS-RAF-MEK)",
      genes: "KRAS,HRAS,NRAS,BRAF,RAF1,MAP2K1,MAP2K2,MAPK1,MAPK3,DUSP6,SPRY2"
    },
    {
      label: "Wnt / β-catenin",
      genes: "WNT1,WNT3A,WNT5A,CTNNB1,APC,AXIN1,AXIN2,GSK3B,TCF7L2,MYC,CCND1,LRP5,LRP6"
    },
    {
      label: "Notch Signaling",
      genes: "NOTCH1,NOTCH2,NOTCH3,NOTCH4,JAG1,JAG2,DLL1,DLL3,DLL4,HES1,HEY1,RBPJ"
    },
    {
      label: "Hedgehog (HH) Signaling",
      genes: "SHH,IHH,DHH,PTCH1,PTCH2,SMO,GLI1,GLI2,GLI3,SUFU,HHIP"
    },
    {
      label: "TGF-β / SMAD",
      genes: "TGFB1,TGFB2,TGFB3,TGFBR1,TGFBR2,SMAD2,SMAD3,SMAD4,SMAD7,ACVR1B,BMP4"
    },
    {
      label: "JAK/STAT",
      genes: "JAK1,JAK2,JAK3,TYK2,STAT1,STAT2,STAT3,STAT4,STAT5A,STAT5B,STAT6,SOCS1,SOCS3"
    },
    {
      label: "NF-κB Signaling",
      genes: "NFKB1,NFKB2,RELA,RELB,REL,IKBKA,IKBKB,NFKBIA,NFKBIB,TNFAIP3,BIRC3"
    },
    {
      label: "VEGF / Angiogenesis",
      genes: "VEGFA,VEGFB,VEGFC,VEGFD,KDR,FLT1,FLT4,HIF1A,EPAS1,FGF2,PDGFA,ANGPT1,ANGPT2"
    },
    {
      label: "RTK / Growth Factor",
      genes: "EGFR,ERBB2,ERBB3,ERBB4,MET,ALK,ROS1,RET,FGFR1,FGFR2,FGFR3,FGFR4,KIT,PDGFRA,PDGFRB"
    },
    {
      label: "Hippo / YAP-TAZ",
      genes: "YAP1,WWTR1,LATS1,LATS2,MST1,MST2,MOB1A,MOB1B,TEAD1,TEAD2,TEAD3,TEAD4,NF2"
    }
  ],

  // ── 3. Cellular Functions (세포 기능별) ──────────────────────────────────
  "Cellular Functions (세포 기능)": [
    {
      label: "Cell Cycle (세포 주기)",
      genes: "CCND1,CCND2,CCND3,CCNE1,CCNE2,CDK2,CDK4,CDK6,CDKN1A,CDKN1B,CDKN2A,CDKN2B,E2F1,RB1,TP53"
    },
    {
      label: "Apoptosis (세포사멸)",
      genes: "BCL2,BCL2L1,BCL2L2,MCL1,BAX,BAK1,BID,BIM,PUMA,NOXA,CASP3,CASP8,CASP9,APAF1,PARP1,XIAP"
    },
    {
      label: "p53 / DNA Damage Response",
      genes: "TP53,MDM2,MDM4,ATM,ATR,CHEK1,CHEK2,BRCA1,BRCA2,CDKN1A,GADD45A,BBC3,BAX,FAS"
    },
    {
      label: "DNA Repair (DNA 수복)",
      genes: "BRCA1,BRCA2,ATM,ATR,CHEK1,CHEK2,PARP1,RAD51,MLH1,MSH2,MSH6,PMS2,ERCC1,ERCC2,XRCC1"
    },
    {
      label: "EMT (상피-중간엽 전환)",
      genes: "CDH1,CDH2,VIM,FN1,SNAI1,SNAI2,TWIST1,TWIST2,ZEB1,ZEB2,MMP2,MMP9,TGFB1"
    },
    {
      label: "Autophagy (자가포식)",
      genes: "BECN1,ATG5,ATG7,ATG12,ATG14,ULK1,ULK2,SQSTM1,MAP1LC3A,MAP1LC3B,MTOR,AMPK"
    },
    {
      label: "Senescence (세포 노화)",
      genes: "CDKN1A,CDKN2A,TP53,RB1,LMNB1,HMGA1,HMGA2,IL6,IL8,CXCL1,MMP3,IGFBP3,SERPINE1"
    },
    {
      label: "Stemness / Cancer Stem Cell",
      genes: "SOX2,OCT4,NANOG,KLF4,MYC,CD44,CD133,ALDH1A1,LGR5,BMI1,EZH2,NOTCH1,WNT1"
    }
  ],

  // ── 4. Immune & Inflammation (면역 및 염증) ───────────────────────────────
  "Immune & Inflammation (면역)": [
    {
      label: "Immune Checkpoint (면역 관문)",
      genes: "PDCD1,CD274,PDCD1LG2,CTLA4,LAG3,TIGIT,HAVCR2,CD276,VTCN1,IDO1,IDO2,CD47,SIRPA"
    },
    {
      label: "T Cell Activation",
      genes: "CD3E,CD4,CD8A,CD8B,CD28,ICOS,CD27,CD137,GZMB,PRF1,IFNG,TNF,IL2,IL2RA"
    },
    {
      label: "NK Cell Markers",
      genes: "NCAM1,KLRB1,KLRD1,KLRK1,NKG7,GZMB,GZMK,PRF1,IFNG,NCR1,NCR3,KIR2DL1"
    },
    {
      label: "Macrophage / Myeloid",
      genes: "CD68,CD163,MRC1,ARG1,NOS2,IL10,IL12A,IL12B,TNF,CXCL8,CCL2,CD14,CSF1R,ITGAM"
    },
    {
      label: "Cytokines & Receptors",
      genes: "IL1A,IL1B,IL2,IL4,IL6,IL8,IL10,IL12A,IL13,IL17A,IL18,TNF,IFNG,IFNA1,TGFB1,CSF2"
    },
    {
      label: "Complement System",
      genes: "C1QA,C1QB,C1QC,C3,C4A,C5,C5AR1,C3AR1,CFB,CFD,CFH,SERPING1,CD55,CD59"
    },
    {
      label: "Interferon Response",
      genes: "IFNA1,IFNB1,IFNG,IFNAR1,IFNAR2,IFNGR1,IFNGR2,IRF1,IRF3,IRF7,IRF9,STAT1,STAT2,MX1,OAS1,ISG15"
    }
  ],

  // ── 5. Epigenetics (후성유전학) ───────────────────────────────────────────
  "Epigenetics (후성유전학)": [
    {
      label: "Histone Methylation",
      genes: "EZH2,EZH1,SUZ12,EED,KMT2A,KMT2B,KMT2C,KMT2D,SETD2,NSD1,NSD2,KDM1A,KDM5C,KDM6A"
    },
    {
      label: "Histone Acetylation",
      genes: "CREBBP,EP300,KAT2A,KAT2B,KAT5,KAT6A,HDAC1,HDAC2,HDAC3,HDAC6,SIRT1,SIRT2"
    },
    {
      label: "DNA Methylation",
      genes: "DNMT1,DNMT3A,DNMT3B,TET1,TET2,TET3,UHRF1,MBD2,MBD4,SMUG1,IDH1,IDH2"
    },
    {
      label: "Chromatin Remodeling (SWI/SNF)",
      genes: "SMARCA4,SMARCA2,SMARCB1,SMARCC1,SMARCC2,SMARCD1,ARID1A,ARID1B,ARID2,PBRM1"
    },
    {
      label: "Polycomb Repressive Complex",
      genes: "EZH2,SUZ12,EED,BMI1,RING1,RNF2,CBX2,CBX4,CBX6,CBX7,CBX8,PCGF2,PCGF4"
    }
  ],

  // ── 6. Metabolism (대사) ──────────────────────────────────────────────────
  "Metabolism (대사)": [
    {
      label: "Warburg Effect / Glycolysis",
      genes: "HK1,HK2,PFKM,PFKL,ALDOA,GAPDH,PGK1,ENO1,PKM,LDHA,LDHB,SLC2A1,SLC2A3,HIF1A"
    },
    {
      label: "Oxidative Phosphorylation",
      genes: "NDUFS1,SDHA,SDHB,UQCRC1,COX4I1,ATP5A1,TFAM,PGC1A,PPARGC1A,PPARGC1B,SIRT1,SIRT3"
    },
    {
      label: "Lipid Metabolism",
      genes: "FASN,ACACA,ACACB,SCD,ELOVL6,HMGCR,SQLE,LDLR,ABCA1,ABCG1,PPARA,PPARG,SREBF1"
    },
    {
      label: "Amino Acid Metabolism",
      genes: "IDO1,IDO2,TDO2,GLS,GLS2,ASNS,PHGDH,PSAT1,PSPH,SLC7A5,SLC7A11,SLC1A5,MTHFR"
    },
    {
      label: "Hypoxia Response",
      genes: "HIF1A,EPAS1,ARNT,SLC2A1,VEGFA,PGK1,LDHA,ENO1,BNIP3,BNIP3L,CA9,CAIX,PDK1"
    },
    {
      label: "mTOR / Nutrient Sensing",
      genes: "MTOR,RPTOR,RICTOR,RPS6KB1,EIF4EBP1,AKT1,TSC1,TSC2,PTEN,AMPK,SESN1,SESN2,REDD1"
    }
  ],

  // ── 7. Transcription Factors (전사인자) ───────────────────────────────────
  "Transcription Factors (전사인자)": [
    {
      label: "MYC Family",
      genes: "MYC,MYCN,MYCL,MAX,MXD1,MXD4,MNT,MLX,MLXIP,MLXIPL"
    },
    {
      label: "FOX Family",
      genes: "FOXO1,FOXO3,FOXO4,FOXA1,FOXA2,FOXM1,FOXP1,FOXP3,FOXC1,FOXC2"
    },
    {
      label: "SOX Family",
      genes: "SOX2,SOX4,SOX9,SOX10,SOX11,SOX17,SOX18,SOXB1,SRY"
    },
    {
      label: "ETS Family",
      genes: "ETS1,ETS2,ERG,ETV1,ETV4,ETV5,FLI1,ELF1,ELF3,ELF5,SPDEF,SPIB,SPIC"
    },
    {
      label: "Nuclear Receptors",
      genes: "AR,ESR1,ESR2,PGR,NR3C1,PPARA,PPARG,PPARD,RARA,RARB,RARG,RXRA,VDR,THRB"
    },
    {
      label: "AP-1 Complex",
      genes: "FOS,FOSB,FOSL1,FOSL2,JUN,JUNB,JUND,ATF1,ATF2,ATF3,ATF4,ATF6,CREB1"
    }
  ],

  // ── 8. Biomarkers (임상 바이오마커) ──────────────────────────────────────
  "Clinical Biomarkers (임상 바이오마커)": [
    {
      label: "Tumor Mutational Burden (TMB) Related",
      genes: "MLH1,MSH2,MSH6,PMS2,POLE,POLD1,BRCA1,BRCA2,ATM,CDK12"
    },
    {
      label: "Microsatellite Instability (MSI)",
      genes: "MLH1,MSH2,MSH6,PMS2,EPCAM,MLH3,MSH3,PMS1,TGFBR2,ACVR2A"
    },
    {
      label: "Homologous Recombination Deficiency (HRD)",
      genes: "BRCA1,BRCA2,ATM,PALB2,RAD51C,RAD51D,BRIP1,CDK12,BARD1,NBN,CHEK2"
    },
    {
      label: "Predictive Biomarkers (면역항암제)",
      genes: "CD274,PDCD1LG2,PDCD1,TMEM173,STING1,CGAS,B2M,HLA-A,HLA-B,HLA-C,JAK1,JAK2,STK11"
    },
    {
      label: "Liquid Biopsy / ctDNA",
      genes: "TP53,KRAS,EGFR,BRAF,PIK3CA,ERBB2,ALK,RET,MET,CDKN2A,RB1,PTEN,APC"
    },
    {
      label: "Hormone Receptor (호르몬 수용체)",
      genes: "ESR1,ESR2,PGR,AR,FOXA1,GATA3,TFF1,TFF3,CCND1,CDK4,CDK6,ERBB2"
    }
  ],

  // ── 9. Roche / KAPA Panels ────────────────────────────────────────────────
  "Roche / KAPA Panels": [
    {
      label: "KAPA HyperCap NHL Panel (Subset)",
      genes: "ABL1,AKT1,ALK,APC,ATM,BRAF,BRCA1,BRCA2,CDH1,CDKN2A,CSF1R,CTNNB1,EGFR,ERBB2,ESR1,EZH2,FBXW7,FGFR1,FGFR2,FGFR3,FLT3,GNA11,GNAQ,GNAS,HNF1A,HRAS,IDH1,IDH2,JAK2,JAK3,KDR,KIT,KRAS,MET,MLH1,MPL,NOTCH1,NPM1,NRAS,PDGFRA,PIK3CA,PTEN,PTPN11,RB1,RET,SMAD4,SMARCB1,SMO,SRC,STK11,TP53,VHL"
    },
    {
      label: "Foundation One CDx (Key Genes)",
      genes: "ABL1,ARID1A,ATM,BRAF,BRCA1,BRCA2,CDK4,CDK6,CDKN2A,EGFR,ERBB2,FGFR1,FGFR2,FGFR3,IDH1,IDH2,KIT,KRAS,MET,MLH1,MSH2,MSH6,MTOR,NRAS,NTRK1,NTRK2,NTRK3,PDGFRA,PIK3CA,PTEN,RET,ROS1,SMAD4,STK11,TP53,TSC1,TSC2,VHL"
    },
    {
      label: "Oncomine Comprehensive Assay (OCA)",
      genes: "ALK,BRAF,EGFR,ERBB2,FGFR1,FGFR2,FGFR3,IDH1,IDH2,KIT,KRAS,MET,NRAS,NTRK1,NTRK2,NTRK3,PDGFRA,PIK3CA,RET,ROS1,TP53"
    }
  ],

  // ── 10. RNA-seq Specific (RNA-seq 특화) ───────────────────────────────────
  "RNA-seq Specific (RNA-seq 특화)": [
    {
      label: "Housekeeping Genes (정규화 참조)",
      genes: "ACTB,GAPDH,B2M,HPRT1,RPL13A,RPLP0,SDHA,TBP,TFRC,UBC,YWHAZ,HMBS"
    },
    {
      label: "Ribosomal Protein Genes",
      genes: "RPS2,RPS3,RPS4X,RPS6,RPS8,RPL3,RPL4,RPL5,RPL6,RPL7,RPL10,RPL13A,RPL23"
    },
    {
      label: "Long Non-coding RNAs (lncRNA)",
      genes: "MALAT1,NEAT1,HOTAIR,XIST,H19,MEG3,GAS5,PTENP1,TERRA,DANCR,SNHG1,SNHG6"
    },
    {
      label: "Fusion Gene Partners (STAR-Fusion)",
      genes: "ALK,ROS1,RET,NTRK1,NTRK2,NTRK3,FGFR1,FGFR2,FGFR3,MET,EGFR,ERBB2,ETV6,RUNX1,BCR,ABL1"
    },
    {
      label: "Splicing Factors",
      genes: "SF3B1,U2AF1,SRSF2,ZRSR2,SF3A1,HNRNPA1,HNRNPA2B1,PTBP1,RBFOX1,RBFOX2,ESRP1,ESRP2"
    }
  ]
};

// ── UI Builder ────────────────────────────────────────────────────────────────

/**
 * Build the full preset UI HTML string.
 * Called from buildRnaGeneViewerTab() in index.html.
 */
function buildPresetUI() {
  const categories = Object.keys(GENE_PRESETS);

  let html = `
  <div style="margin-bottom:12px">
    <div style="font-size:.75rem;font-weight:600;color:var(--text);margin-bottom:8px">
      📂 유전자 그룹 프리셋 선택 (${categories.reduce((s, c) => s + GENE_PRESETS[c].length, 0)}개 그룹 / ${categories.length}개 카테고리)
    </div>

    <!-- Category + Subcategory dropdowns -->
    <div style="display:flex;gap:8px;margin-bottom:8px;flex-wrap:wrap;align-items:center">
      <select id="preset-category-select"
        style="padding:5px 8px;border:1px solid var(--border);border-radius:4px;font-size:.78rem;min-width:200px"
        onchange="updatePresetSubcategories()">
        <option value="">── 카테고리 선택 ──</option>`;

  categories.forEach(cat => {
    const count = GENE_PRESETS[cat].length;
    html += `<option value="${cat}">${cat} (${count}개)</option>`;
  });

  html += `
      </select>

      <select id="preset-subcategory-select"
        style="padding:5px 8px;border:1px solid var(--border);border-radius:4px;font-size:.78rem;min-width:220px;display:none"
        onchange="applyPresetSelection()">
        <option value="">── 그룹 선택 ──</option>
      </select>

      <span id="preset-gene-count" style="font-size:.72rem;color:var(--text-muted)"></span>
    </div>

    <!-- Quick-access pills -->
    <div style="font-size:.72rem;color:var(--text-muted);display:flex;flex-wrap:wrap;gap:5px;align-items:center">
      <span style="font-weight:600;color:var(--text);white-space:nowrap">자주 찾는 그룹:</span>`;

  const quickPills = [
    { cat: "Cellular Functions (세포 기능)", name: "Apoptosis (세포사멸)" },
    { cat: "Cellular Functions (세포 기능)", name: "Cell Cycle (세포 주기)" },
    { cat: "Cellular Functions (세포 기능)", name: "EMT (상피-중간엽 전환)" },
    { cat: "Signaling Pathways (신호전달)", name: "PI3K/AKT/mTOR" },
    { cat: "Signaling Pathways (신호전달)", name: "MAPK/ERK (RAS-RAF-MEK)" },
    { cat: "Immune & Inflammation (면역)", name: "Immune Checkpoint (면역 관문)" },
    { cat: "Immune & Inflammation (면역)", name: "T Cell Activation" },
    { cat: "Clinical Biomarkers (임상 바이오마커)", name: "Microsatellite Instability (MSI)" },
    { cat: "Clinical Biomarkers (임상 바이오마커)", name: "Homologous Recombination Deficiency (HRD)" },
    { cat: "RNA-seq Specific (RNA-seq 특화)", name: "Housekeeping Genes (정규화 참조)" },
    { cat: "Roche / KAPA Panels", name: "KAPA HyperCap NHL Panel (Subset)" },
  ];

  quickPills.forEach(pill => {
    const catData = GENE_PRESETS[pill.cat];
    if (!catData) return;
    const preset = catData.find(p => p.label === pill.name);
    if (!preset) return;
    const safeGenes = preset.genes.replace(/'/g, "\\'");
    html += `<span
      style="cursor:pointer;background:rgba(68,114,196,0.1);color:var(--primary);padding:2px 8px;border-radius:12px;border:1px solid rgba(68,114,196,0.2);white-space:nowrap"
      onclick="gvApplyPreset('${safeGenes}')"
      title="${preset.genes}">${preset.label}</span>`;
  });

  html += `
    </div>
  </div>`;

  return html;
}

/** Update subcategory dropdown when category changes */
function updatePresetSubcategories() {
  const catEl = document.getElementById('preset-category-select');
  const subEl = document.getElementById('preset-subcategory-select');
  const countEl = document.getElementById('preset-gene-count');
  if (!catEl || !subEl) return;

  const category = catEl.value;
  if (!category || !GENE_PRESETS[category]) {
    subEl.style.display = 'none';
    if (countEl) countEl.textContent = '';
    return;
  }

  const items = GENE_PRESETS[category];
  let options = '<option value="">── 그룹 선택 ──</option>';
  items.forEach(item => {
    const geneCount = item.genes.split(',').length;
    options += `<option value="${item.genes}">${item.label} (${geneCount}개 유전자)</option>`;
  });

  subEl.innerHTML = options;
  subEl.style.display = 'block';
  subEl.value = '';
  if (countEl) countEl.textContent = '';
}

/** Apply selected subcategory preset to the gene input */
function applyPresetSelection() {
  const subEl = document.getElementById('preset-subcategory-select');
  const countEl = document.getElementById('preset-gene-count');
  if (!subEl) return;
  const genes = subEl.value;
  if (genes) {
    gvApplyPreset(genes);
  }
}

/** Set gene input value and update count display */
function gvApplyPreset(genes) {
  const inputEl = document.getElementById('gv-multi-genes');
  const countEl = document.getElementById('preset-gene-count');
  if (inputEl) inputEl.value = genes;
  if (countEl) {
    const n = genes.split(',').filter(g => g.trim()).length;
    countEl.textContent = `→ ${n}개 유전자 선택됨`;
  }
}
