version development

## Collect intervals of the genome that are covered by at least a certain number
## of reads in a given sample.
##
## Known issues:
## The required diskspace is quite large (equivalent to storing the bam itself).
## It is recommended to copy the output to another bucket and delete the bucket
## used to run this workflow.

import "runtimes.wdl"


workflow CollectCoveredRegions {
    input {
        File? interval_list
        File ref_fasta
        File ref_fasta_index
        File ref_dict

        String sample_name
        File bam
        File bai

        # arguments
        Int min_read_depth_threshold = 1
        Boolean paired_end = false
        String output_format = "interval_list"  # bam, bed, interval_list

        Runtime collect_covered_regions_runtime = Runtimes.collect_covered_regions_runtime

        # Needs docker image with bedtools, samtools, and gatk
        # todo: find smaller image. This one takes ~13 mins to spin up.
        String docker = "us.gcr.io/broad-dsp-gcr-public/terra-jupyter-gatk"  # 27.5GB
        File? gatk_override
        Int preemptible = 1
        Int max_retries = 1

        # memory assignments in MB
        Int mem_collect_covered_regions = 8192

        # runtime assignments in minutes (for HPC cluster)
        Int time_startup = 15
        Int time_collect_covered_regions = 300
    }

    call runtimes.DefineRuntimes as Runtimes {
        input:
            jupyter_docker = docker,
            gatk_override = gatk_override,
            preemptible = preemptible,
            max_retries = max_retries,
            mem_collect_covered_regions = mem_collect_covered_regions,
            time_startup = time_startup,
            time_collect_covered_regions = time_collect_covered_regions
    }

    call runtimes.UpdateRuntimeParameters as CollectCoverageRegionsRuntime {
        input:
            runtime_params = collect_covered_regions_runtime,
            disk = 10 + ceil(1.2 * size(bam, "GB"))
    }

    call CollectCoveredRegions {
        input:
            ref_fasta = ref_fasta,
            ref_fasta_index = ref_fasta_index,
            ref_dict = ref_dict,
            interval_list = interval_list,
            sample_name = sample_name,
            input_bam = bam,
            input_bai = bai,
            min_read_depth_threshold = min_read_depth_threshold,
            paired_end = paired_end,
            output_format = output_format,
            runtime_params = CollectCoverageRegionsRuntime.params,
    }

    output {
        File regions_bed = CollectCoveredRegions.bed
        File? regions_bam = CollectCoveredRegions.bam
        File? regions_bai = CollectCoveredRegions.bai
        File? regions_interval_list = CollectCoveredRegions.intervals
    }
}

task CollectCoveredRegions {
    input {
        File? ref_fasta
        File? ref_fasta_index
        File ref_dict
        File? interval_list

        Array[String]? read_filters
        String? print_reads_extra_args

        String? sample_name
        File input_bam
        File input_bai

        Int min_read_depth_threshold = 1
        Boolean paired_end = false
        String output_format = "bed"  # bam, bed, interval_list

        Runtime runtime_params
    }

    Int max = if paired_end then ceil(min_read_depth_threshold / 2) else min_read_depth_threshold

    String name = if defined(sample_name) then sample_name else basename(input_bam, ".bam")

    String filtered_bam = name + ".filtered.bam"
    String filtered_bai = name + ".filtered.bai"

    String tag = ".covered_regions.minDepth" + min_read_depth_threshold
    String covered_regions_bed = name + tag + ".bed"
    String covered_regions_bam = name + tag + ".bam"
    String covered_regions_bai = name + tag + ".bai"
    String covered_regions_interval_list = name + tag + ".interval_list"

    String dollar = "$"

    command <<<
        set -e
        ~{"export GATK_LOCAL_JAR=" + runtime_params.jar_override}

        echo "..."
        echo "$(date +'%H:%M:%S.%3N') Apply Read Filters that are automatically applied to the data by the Engine before processing by Mutect2:"
        echo "..."

        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            PrintReads \
            -I '~{input_bam}' \
            -O '~{filtered_bam}' \
            ~{"-R '" + ref_fasta + "'"} \
            ~{"-L '" + interval_list + "'"} \
            --read-filter NonChimericOriginalAlignmentReadFilter \
            --read-filter NotSecondaryAlignmentReadFilter \
            --read-filter GoodCigarReadFilter \
            --read-filter NonZeroReferenceLengthAlignmentReadFilter \
            --read-filter PassesVendorQualityCheckReadFilter \
            --read-filter MappedReadFilter \
            --read-filter MappingQualityAvailableReadFilter \
            --read-filter NotDuplicateReadFilter \
            --read-filter MappingQualityReadFilter \
            --read-filter MappingQualityNotZeroReadFilter \
            --read-filter WellformedReadFilter \
            ~{true="--read-filter " false="" defined(read_filters)}~{default="" sep=" --read-filter " read_filters} \
            ~{print_reads_extra_args}

        echo "..."
        echo "$(date +'%H:%M:%S.%3N') Collecting BEDGRAPH summaries of feature coverage and removing regions below ~{min_read_depth_threshold} read depth:"

        set -x
        bedtools genomecov \
            -ibam '~{filtered_bam}' \
            -max ~{max} \
            -bg \
            ~{true="-pc " false="" paired_end} \
        | awk '~{dollar}4>=~{max}' \
        | bedtools merge -c 4 -o min -d 1 -i stdin \
        > '~{covered_regions_bed}'
        set +x

        echo "$(date +'%H:%M:%S.%3N') clean up"

        rm -f '~{filtered_bam}' '~{filtered_bai}'

        if [[ "~{output_format}" == "bam" ]] ; then
            echo "$(date +'%H:%M:%S.%3N') Create bam from bed file:"
            echo "Replace target names with dots to avoid bedtools error [E::bam_aux_next] Corrupted aux data for read ..."

            set -x
            awk 'BEGIN{OFS="\t"}{~{dollar}4 = "."; print}' '~{covered_regions_bed}' \
                > 'tmp.~{covered_regions_bed}'
            mv 'tmp.~{covered_regions_bed}' '~{covered_regions_bed}'

            bedtools bedtobam \
                -i '~{covered_regions_bed}' \
                -g '~{ref_fasta_index}' \
                > 'tmp.~{name}.bam'
            samtools addreplacerg \
                -r ID:~{name} \
                -r SM:~{name} \
                -o 'tmp.annotated.~{name}.bam' \
                'tmp.~{name}.bam'
            set +x
            gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
                SortSam \
                -I 'tmp.annotated.~{name}.bam' \
                -O '~{covered_regions_bam}' \
                --SORT_ORDER coordinate \
                --CREATE_INDEX true

            rm -f 'tmp.~{name}.bam' 'tmp.annotated.~{name}.bam'
        fi

        if [[ "~{output_format}" == "interval_list" ]] ; then
            echo "$(date +'%H:%M:%S.%3N') Create interval_list from bed file:"

            gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
                BedToIntervalList \
                -I '~{covered_regions_bed}' \
                -O '~{covered_regions_interval_list}' \
                -SD '~{ref_dict}'
        fi

        echo "$(date +'%H:%M:%S.%3N') SUCCESS"
        echo "..."
    >>>

    output {
        File bed = covered_regions_bed
        File? bam = covered_regions_bam
        File? bai = covered_regions_bai
        File? intervals = covered_regions_interval_list
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        # ref_fasta: {localization_optional: true}
        # ref_fasta_index: {localization_optional: true}
        # ref_dict: {localization_optional: true}
        input_bam: {localization_optional: true}
        input_bai: {localization_optional: true}
    }
}
