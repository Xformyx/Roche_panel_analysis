/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_INTERACTIVE_PLOTS  —  Interactive Plotly visualizations (HTML)
 *
 *  Generates:
 *    - Interactive Count distribution (log2 CPM)
 *    - Interactive Top expressed genes (TPM)
 *    - Interactive MA-like plot (log2(TPM) vs log2(CPM))
 * ─────────────────────────────────────────────────────────────────────────────
 */
process RNASEQ_INTERACTIVE_PLOTS {
    tag "$sample_id"
    label 'process_medium'
    publishDir { "${params.outdir}/${sample_id}/expression_plots" }, mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(summary_tsv)

    output:
    tuple val(sample_id), path("${sample_id}_interactive_*.html"), emit: html_plots

    script:
    """
    #!/usr/bin/env python3
    import pandas as pd
    import plotly.express as px
    import plotly.graph_objects as go
    import numpy as np

    sample_id = "${sample_id}"
    df = pd.read_csv("${summary_tsv}", sep="\\t")

    # Pre-compute log columns on the full dataframe before subsetting
    df['log2TPM'] = np.log2(df['TPM'] + 1)

    # 1. Count Distribution (Interactive)
    df_expr = df[df['count'] > 0].copy()
    fig1 = px.histogram(df_expr, x="log2CPM", nbins=80, 
                        title=f"{sample_id} — Read Count Distribution (log2 CPM)",
                        labels={"log2CPM": "log2(CPM + 1)"},
                        color_discrete_sequence=["#4472C4"],
                        hover_data=["gene_symbol", "gene_id"])
    fig1.add_vline(x=np.log2(2), line_dash="dash", line_color="red")
    fig1.write_html(f"{sample_id}_interactive_count_distribution.html")

    # 2. Top 30 Expressed Genes (Interactive)
    top30 = df.nlargest(30, 'TPM').copy()
    top30['label'] = np.where(top30['gene_symbol'] != top30['gene_id'], 
                              top30['gene_symbol'], 
                              top30['gene_id'].str.replace(r'\\.[0-9]+\$', '', regex=True))
    top30 = top30.sort_values('TPM', ascending=True)
    fig2 = px.bar(top30, x="TPM", y="label", orientation='h',
                  title=f"{sample_id} — Top 30 Expressed Genes (TPM)",
                  color_discrete_sequence=["#ED7D31"],
                  hover_data=["gene_id", "count", "CPM"])
    fig2.write_html(f"{sample_id}_interactive_top30_genes.html")

    # 3. MA-like Plot (log2(TPM+1) vs log2(CPM+1)) (Interactive)
    fig3 = px.scatter(df_expr, x="log2CPM", y="log2TPM", 
                      hover_name="gene_symbol", hover_data=["gene_id", "count", "TPM"],
                      title=f"{sample_id} — Expression MA-like Plot",
                      labels={"log2CPM": "log2(CPM + 1)", "log2TPM": "log2(TPM + 1)"},
                      opacity=0.5, color_discrete_sequence=["#7030A0"])
    fig3.write_html(f"{sample_id}_interactive_ma_plot.html")

    print(f"Interactive plots generated for {sample_id}")
    """
}
