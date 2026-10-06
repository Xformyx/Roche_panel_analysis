/*
 * QC Report Sub-workflow
 *
 * Alignment metrics, insert size, MarkDuplicates, HsMetrics,
 * on-target counts, mismatch rate
 *
 * BED usage:
 *   capture_bed  → VarDict (upstream) + MISMATCH_RATE
 *   primary_bed  → COUNT_READS (on-target reads, strict target region)
 *   bait_ilist   → HsMetrics BAIT_INTERVALS and TARGET_INTERVALS
 *                  (pre-built capture interval_list; if null, capture_bed is converted on-the-fly)
 *                  White paper uses the same capture interval list for both.
 */

include { COLLECT_ALIGNMENT_METRICS                       } from '../modules/qc_metrics'
include { MARK_DUPLICATES                                 } from '../modules/qc_metrics'
include { COLLECT_INSERT_SIZE                              } from '../modules/qc_metrics'
include { REFERENCE_BUILD_INFO                            } from '../modules/qc_metrics'
include { COUNT_READS as COUNT_READS_CAPTURE              } from '../modules/qc_metrics'
include { COUNT_READS as COUNT_READS_PRIMARY              } from '../modules/qc_metrics'
include { BED_TO_INTERVAL_LIST as BED_TO_ILIST_CAPTURE    } from '../modules/hs_metrics'
include { COLLECT_HS_METRICS as HS_METRICS_ALIGNED        } from '../modules/hs_metrics'
include { COLLECT_HS_METRICS as HS_METRICS_DEDUPED        } from '../modules/hs_metrics'
include { MISMATCH_RATE                                   } from '../modules/mismatch_rate'

workflow QC_REPORT {

    take:
    aligned_bam_ch    // tuple(sample_id, bam, bai) - first-pass aligned sorted
    deduped_bam_ch    // tuple(sample_id, bam) - deduped sorted
    genome_fasta      // path
    genome_dict       // path
    genome_fai        // path
    capture_bed       // path  — VarDict BED / mismatch rate
    primary_bed       // path  — on-target reads (CountReads)
    bait_ilist        // path? — HsMetrics BAIT and TARGET (null → convert capture_bed)
    blocklist         // path
    bsgenome_ref      // val
    reference_label   // val   — params.reference ('hg38', 'hg19', …)

    main:

    // Prepare labeled channels for processes that handle both aligned and deduped BAMs
    aligned_labeled = aligned_bam_ch.map { sid, bam, bai -> tuple(sid, 'aligned', bam) }
    deduped_labeled = deduped_bam_ch.map { sid, bam -> tuple(sid, 'umi_deduped', bam) }

    // 1. Alignment summary metrics (both BAMs)
    COLLECT_ALIGNMENT_METRICS(
        aligned_labeled.mix(deduped_labeled),
        genome_fasta,
        genome_dict,
        genome_fai
    )

    // 2. Insert size metrics (both BAMs)
    COLLECT_INSERT_SIZE(
        aligned_labeled.mix(deduped_labeled)
    )

    // 3. MarkDuplicates (aligned BAM only)
    aligned_for_markdup = aligned_bam_ch.map { sid, bam, bai -> tuple(sid, bam) }
    MARK_DUPLICATES(aligned_for_markdup)

    // 4a. On-target read counts — CAPTURE BED (experiment success / broad capture region)
    //     This is the main "On-Target %" shown in the QC summary (experiment evaluation)
    COUNT_READS_CAPTURE(
        aligned_labeled.mix(deduped_labeled),
        genome_fasta,
        genome_dict,
        genome_fai,
        capture_bed,
        'capture'
    )

    // 4b. On-target read counts — PRIMARY BED (analytical target / strict region)
    //     Used as supplementary KPI: "are enough reads on the regions we report?"
    COUNT_READS_PRIMARY(
        aligned_labeled.mix(deduped_labeled),
        genome_fasta,
        genome_dict,
        genome_fai,
        primary_bed,
        'primary'
    )

    // 5. Record which reference build actually produced these results
    sample_ids_ch = aligned_bam_ch.map { sid, bam, bai -> sid }
    REFERENCE_BUILD_INFO(sample_ids_ch, genome_fai, reference_label, genome_fasta.name)

    // 6. HsMetrics BAIT and TARGET are the same capture interval list.
    //    A pre-built bait list is the capture targets in interval_list form.
    //    If it is absent, convert capture_bed on the fly and use that for both.
    if (bait_ilist) {
        hs_ilist_ch = sample_ids_ch.map { sid -> tuple(sid, bait_ilist) }
    } else {
        BED_TO_ILIST_CAPTURE(sample_ids_ch, capture_bed, genome_dict, "capture_bait")
        hs_ilist_ch = BED_TO_ILIST_CAPTURE.out.interval_list
            .map { sid, name, ilist -> tuple(sid, ilist) }
    }

    // 7. HsMetrics — aligned BAM. The same interval list is passed as BAIT and TARGET.
    hs_aligned_input = aligned_bam_ch
        .join(hs_ilist_ch)
        .map { sid, bam, bai, ilist -> tuple(sid, 'aligned', bam, ilist, ilist) }

    HS_METRICS_ALIGNED(hs_aligned_input, genome_fasta, genome_dict, genome_fai)

    // 8. HsMetrics — UMI deduped BAM
    hs_deduped_input = deduped_bam_ch
        .join(hs_ilist_ch)
        .map { sid, bam, ilist -> tuple(sid, 'umi_deduped', bam, ilist, ilist) }

    HS_METRICS_DEDUPED(hs_deduped_input, genome_fasta, genome_dict, genome_fai)

    // 9. Mismatch rate (deduped BAM, capture BED — wider region for background calc)
    MISMATCH_RATE(deduped_bam_ch, capture_bed, blocklist, bsgenome_ref)

    emit:
    alignment_metrics        = COLLECT_ALIGNMENT_METRICS.out.metrics
    insert_metrics           = COLLECT_INSERT_SIZE.out.metrics
    markdup_metrics          = MARK_DUPLICATES.out.metrics
    ontarget_counts_capture  = COUNT_READS_CAPTURE.out.counts  // capture BED reads (main On-Target %)
    ontarget_counts_primary  = COUNT_READS_PRIMARY.out.counts  // primary BED reads (supplementary)
    hs_metrics_aln           = HS_METRICS_ALIGNED.out.hs_metrics
    hs_metrics_ded           = HS_METRICS_DEDUPED.out.hs_metrics
    mismatch                 = MISMATCH_RATE.out.mismatch
    reference_build          = REFERENCE_BUILD_INFO.out.info
}
