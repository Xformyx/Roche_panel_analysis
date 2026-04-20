/*
 * UMI Preprocessing Sub-workflow
 *
 * FASTQ -> unmapped BAM -> UMI extract -> trim -> subsample -> align ->
 * merge UMI tags -> group by UMI -> consensus -> filter -> 2nd align ->
 * merge -> clip -> final sorted BAM
 */

include { FASTQ_TO_SAM         } from '../modules/fastq_to_sam'
include { EXTRACT_UMIS          } from '../modules/extract_umis'
include { SAM_TO_FASTQ          } from '../modules/sam_to_fastq'
include { FASTP                 } from '../modules/fastp'
include { SEQTK_SUBSAMPLE       } from '../modules/seqtk_subsample'
include { BWA_ALIGN             } from '../modules/bwa_align'
include { BWA_CONSENSUS_ALIGN   } from '../modules/bwa_align'
include { SORT_SAM_QUERYNAME as SORT_ALIGNED_QN       } from '../modules/sort_sam'
include { SORT_SAM_QUERYNAME as SORT_DEDUPED_QN       } from '../modules/sort_sam'
include { SORT_SAM_QUERYNAME as SORT_CONSENSUS_FLT_QN } from '../modules/sort_sam'
include { SORT_SAM_QUERYNAME as SORT_CONSENSUS_MAP_QN } from '../modules/sort_sam'
include { SORT_SAM_COORDINATE as SORT_ALIGNED_COORD   } from '../modules/sort_sam'
include { SORT_SAM_COORDINATE_FINAL as SORT_FINAL_COORD } from '../modules/sort_sam'
include { MERGE_BAM_ALIGNMENT   } from '../modules/merge_bam'
include { MERGE_CONSENSUS_BAM   } from '../modules/merge_bam'
include { GROUP_READS_BY_UMI    } from '../modules/group_reads_umi'
include { CALL_CONSENSUS        } from '../modules/call_consensus'
include { FILTER_CONSENSUS      } from '../modules/filter_consensus'
include { CLIP_BAM              } from '../modules/clip_bam'

workflow UMI_PREPROCESSING {

    take:
    samples_ch    // tuple(sample_id, fastq_1, fastq_2)
    genome_fasta  // path to reference genome
    genome_dict   // path to sequence dictionary (.dict)
    genome_fai    // path to fasta index (.fai)
    genome_idx    // path to BWA index files

    main:

    // 1. FASTQ -> unmapped BAM
    FASTQ_TO_SAM(samples_ch)

    // 2. Extract UMIs
    EXTRACT_UMIS(FASTQ_TO_SAM.out.unmapped_bam)

    // 3. BAM -> FASTQ (with UMI clipping)
    SAM_TO_FASTQ(EXTRACT_UMIS.out.umi_bam)

    // 4. Adapter + quality trimming
    FASTP(SAM_TO_FASTQ.out.fastq)

    // 5. Subsample reads
    SEQTK_SUBSAMPLE(FASTP.out.trimmed)

    // 6. First BWA alignment (trimmed reads, not subsampled - subsample is a cap)
    BWA_ALIGN(FASTP.out.trimmed, genome_fasta, genome_idx)

    // 7. Sort aligned BAM by queryname
    SORT_ALIGNED_QN(BWA_ALIGN.out.aligned_bam)

    // 8. Merge UMI info back into aligned reads
    //    Combine sorted aligned with UMI-extracted unmapped
    merge_input = SORT_ALIGNED_QN.out.sorted_bam
        .join(EXTRACT_UMIS.out.umi_bam)

    MERGE_BAM_ALIGNMENT(merge_input, genome_fasta, genome_dict, genome_fai)

    // 9. Group reads by UMI
    GROUP_READS_BY_UMI(MERGE_BAM_ALIGNMENT.out.merged_bam)

    // 10. Call molecular consensus reads
    CALL_CONSENSUS(GROUP_READS_BY_UMI.out.grouped_bam)

    // 11. Filter consensus reads
    FILTER_CONSENSUS(CALL_CONSENSUS.out.consensus_bam, genome_fasta, genome_dict, genome_fai)

    // 12. Sort filtered consensus by queryname, then back to FASTQ
    SORT_CONSENSUS_FLT_QN(FILTER_CONSENSUS.out.filtered_bam)

    // Re-use SAM_TO_FASTQ for consensus
    // Need a separate include or alias - use the same process with different name
    consensus_fastq = SORT_CONSENSUS_FLT_QN.out.sorted_bam
        .map { sample_id, bam -> tuple(sample_id, bam) }

    SAM_TO_FASTQ_CONSENSUS(consensus_fastq)

    // 13. Second BWA alignment on consensus reads
    BWA_CONSENSUS_ALIGN(SAM_TO_FASTQ_CONSENSUS.out.fastq, genome_fasta, genome_idx)

    // 14. Sort consensus-mapped BAM by queryname
    SORT_CONSENSUS_MAP_QN(BWA_CONSENSUS_ALIGN.out.consensus_bam)

    // 15. Final merge: consensus-mapped + filtered-unmapped
    final_merge_input = SORT_CONSENSUS_MAP_QN.out.sorted_bam
        .join(SORT_CONSENSUS_FLT_QN.out.sorted_bam)

    MERGE_CONSENSUS_BAM(final_merge_input, genome_fasta, genome_dict, genome_fai)

    // 16. Sort deduped BAM by queryname (for clipping)
    SORT_DEDUPED_QN(MERGE_CONSENSUS_BAM.out.deduped_bam)

    // 17. Clip overlapping reads
    CLIP_BAM(SORT_DEDUPED_QN.out.sorted_bam, genome_fasta, genome_dict, genome_fai)

    // 18. Final coordinate sort + index
    SORT_FINAL_COORD(CLIP_BAM.out.clipped_bam)

    // 19. Also sort the first-pass aligned BAM for QC
    SORT_ALIGNED_COORD(BWA_ALIGN.out.aligned_bam)

    emit:
    final_bam    = SORT_FINAL_COORD.out.sorted_bam      // tuple(sample_id, bam, bai) - clipov sorted
    aligned_bam  = SORT_ALIGNED_COORD.out.sorted_bam    // tuple(sample_id, bam, bai) - first-pass for QC
    deduped_bam  = MERGE_CONSENSUS_BAM.out.deduped_bam  // tuple(sample_id, bam) - deduped sorted
    fastp_report = FASTP.out.report
}

// Aliased SAM_TO_FASTQ for consensus reads
process SAM_TO_FASTQ_CONSENSUS {
    tag "$sample_id"
    label 'process_medium'

    input:
    tuple val(sample_id), path(input_bam)

    output:
    tuple val(sample_id), path("${sample_id}_consensus_R1.fastq"), path("${sample_id}_consensus_R2.fastq"), emit: fastq

    script:
    def java_opts = "-Xmx${task.memory.toGiga()}g"
    """
    gatk --java-options "${java_opts}" SamToFastq \
        -I ${input_bam} \
        -F ${sample_id}_consensus_R1.fastq \
        -F2 ${sample_id}_consensus_R2.fastq \
        --CLIPPING_ATTRIBUTE XT \
        --CLIPPING_ACTION 2
    """
}
