/*
 * ─────────────────────────────────────────────────────────────────────────────
 *  RNASEQ_QC_SUMMARY  —  Parse STAR/featureCounts/fastp outputs into a
 *                         single JSON consumed by the web UI /api/orders/<id>/qc_data
 *
 *  Output: <sample_id>_rna_qc.json  (published to QC_report/)
 * ─────────────────────────────────────────────────────────────────────────────
 */
process RNASEQ_QC_SUMMARY {
    tag "$sample_id"
    label 'process_low'
    publishDir "${params.outdir}/${sample_id}/QC_report", mode: params.publish_dir_mode

    input:
    tuple val(sample_id), path(star_log)
    tuple val(sample_id2), path(fastp_json)
    tuple val(sample_id3), path(fc_summary)
    tuple val(sample_id4), path(flagstat)

    output:
    tuple val(sample_id), path("${sample_id}_rna_qc.json"), emit: qc_json

    script:
    """
    #!/usr/bin/env python3
    import json, re, sys

    sample_id = "${sample_id}"

    # ── 1. Parse STAR Log.final.out ──────────────────────────────────────────
    star = {}
    try:
        with open("${star_log}") as fh:
            for line in fh:
                line = line.strip()
                if "|" in line:
                    parts = line.split("|")
                    if len(parts) == 2:
                        k = parts[0].strip().rstrip(" :")
                        v = parts[1].strip().rstrip("%")
                        star[k] = v
    except Exception as e:
        star["parse_error"] = str(e)

    def _star(key, default=""):
        return star.get(key, default)

    star_summary = {
        "total_reads":              _star("Number of input reads"),
        "uniquely_mapped":          _star("Uniquely mapped reads number"),
        "uniquely_mapped_pct":      _star("Uniquely mapped reads %"),
        "multi_mapped":             _star("Number of reads mapped to multiple loci"),
        "multi_mapped_pct":         _star("% of reads mapped to multiple loci"),
        "unmapped_too_short_pct":   _star("% of reads unmapped: too short"),
        "unmapped_other_pct":       _star("% of reads unmapped: other"),
        "avg_mapped_length":        _star("Average mapped length"),
        "avg_input_read_length":    _star("Average input read length"),
        "splices_total":            _star("Number of splices: Total"),
        "splices_annotated":        _star("Number of splices: Annotated (sjdb)"),
        "mismatch_rate_per_base":   _star("Mismatch rate per base, %"),
        "deletion_rate_per_base":   _star("Deletion rate per base"),
        "insertion_rate_per_base":  _star("Insertion rate per base"),
    }

    # ── 2. Parse fastp JSON ───────────────────────────────────────────────────
    fastp_summary = {}
    try:
        with open("${fastp_json}") as fh:
            fj = json.load(fh)
        s_before = fj.get("summary", {}).get("before_filtering", {})
        s_after  = fj.get("summary", {}).get("after_filtering", {})
        fc_res   = fj.get("filtering_result", {})
        fastp_summary = {
            "before_total_reads":       s_before.get("total_reads", 0),
            "before_total_bases":       s_before.get("total_bases", 0),
            "before_q20_rate":          s_before.get("q20_rate", 0),
            "before_q30_rate":          s_before.get("q30_rate", 0),
            "before_gc_content":        s_before.get("gc_content", 0),
            "after_total_reads":        s_after.get("total_reads", 0),
            "after_total_bases":        s_after.get("total_bases", 0),
            "after_q20_rate":           s_after.get("q20_rate", 0),
            "after_q30_rate":           s_after.get("q30_rate", 0),
            "after_gc_content":         s_after.get("gc_content", 0),
            "after_read1_mean_length":  s_after.get("read1_mean_length", 0),
            "after_read2_mean_length":  s_after.get("read2_mean_length", 0),
            "passed_filter_reads":      fc_res.get("passed_filter_reads", 0),
            "low_quality_reads":        fc_res.get("low_quality_reads", 0),
            "too_short_reads":          fc_res.get("too_short_reads", 0),
            "adapter_trimmed_reads":    fj.get("adapter_cutting", {}).get("adapter_trimmed_reads", 0),
        }
    except Exception as e:
        fastp_summary["parse_error"] = str(e)

    # ── 3. Parse featureCounts summary ───────────────────────────────────────
    fc_summary_data = {}
    try:
        with open("${fc_summary}") as fh:
            lines = fh.readlines()
        # Header: Status  <bam_path>
        if len(lines) >= 2:
            header = lines[0].strip().split("\\t")
            for line in lines[1:]:
                parts = line.strip().split("\\t")
                if len(parts) >= 2:
                    fc_summary_data[parts[0]] = int(parts[1]) if parts[1].isdigit() else parts[1]
    except Exception as e:
        fc_summary_data["parse_error"] = str(e)

    # ── 4. Parse samtools flagstat ────────────────────────────────────────────
    flagstat_data = {}
    try:
        with open("${flagstat}") as fh:
            for line in fh:
                line = line.strip()
                m = re.match(r"(\\d+) \\+ (\\d+) (.+)", line)
                if m:
                    key = m.group(3).split("(")[0].strip().replace(" ", "_")
                    flagstat_data[key] = int(m.group(1))
    except Exception as e:
        flagstat_data["parse_error"] = str(e)

    # ── 5. Assemble final QC JSON ─────────────────────────────────────────────
    qc = {
        "sample_id":        sample_id,
        "pipeline":         "rnaseq",
        "star":             star_summary,
        "fastp":            fastp_summary,
        "featurecounts":    fc_summary_data,
        "flagstat":         flagstat_data,
    }

    with open(f"{sample_id}_rna_qc.json", "w") as fh:
        json.dump(qc, fh, indent=2)

    print(f"QC JSON written: {sample_id}_rna_qc.json")
    """
}
