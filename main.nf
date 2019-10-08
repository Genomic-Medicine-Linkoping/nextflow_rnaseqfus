#!/usr/bin/dev nextflow

/* Input files */ 
params.outdir = "/data/bnf/dev/sima/rnaSeq_fus/results"
params.reads = "/data/NextSeq1/190829_NB501697_0156_AH35YWBGXC/Data/Intensities/BaseCalls/ALL354A189_122-60853_S43_R{1,2}_001.fastq.gz"
smpl_id = 'ALL354A189_122-60853_S43_R'


//params.genome_fasta = "/data/bnf/dev/sima/rnaSeq_fus/data/hg_files/hg38/hg38.fa" //genome fasta file (Not using this file)
//params.genome_gtf = "/data/bnf/dev/sima/rnaSeq_fus/data/hg_files/hg38/gencode.v31.chr_patch_hapl_scaff.annotation.gtf" //Annotation file(not using this file)

params.genome_fasta = "/data/bnf/dev/sima/rnaSeq_fus/data/hg_files/Homo_sapiens.GRCh38.dna_sm.primary_assembly.fa" //fasta file from ensembl
params.genome_gtf = "/data/bnf/dev/sima/rnaSeq_fus/data/hg_files/gtf/Homo_sapiens.GRCh38.98.gtf" //fasta file from ensembl

/* fastqscreen genome config file */
params.genome_conf = "/data/bnf/dev/sima/rnaSeq_fus/data/fastqScreen/FastQ_Screen_Genomes/fastq_screen.conf"


params.fusionCatcher_ref= "/data/bnf/dev/sima/rnaSeq_fus/data/fusioncatcher/human_v95"
params.star_fusion_ref = "/data/bnf/dev/sima/rnaSeq_fus/data/starFusion/ctat_genome_lib_build_dir"
/* Jaffa ref files have to be in the same directory where the binary has been installed, so it is downloaded in the container or the path has to be specified. */


// Quantificatin files
decoys_file ="/data/bnf/dev/sima/rnaSeq_fus/data/salmon/decoys.txt"
params.ref_salmon = "/data/bnf/dev/sima/rnaSeq_fus/data/salmon/gentrome.fa" //has to be transcriptome

//Provider  files
params.ref_bed = "/data/bnf/sw/provider/HPA_1000G_final_38.bed"
params.ref_bedXy= "/data/bnf/sw/provider/xy_38.bed"
//BodyCov
//params.ref_rseqc_bed ="/data/bnf/dev/sima/rnaSeq_fus/data/RseQC/hg38_RefSeq_new.bed" //cat hg38_RefSeq.bed| sed 's/^chr//' > hg38_RefSeq_new.bed (nochr)
//params.ref_rseqc_bed= "/data/bnf/ref/b37/b37_RefSeq.bed"
//params.ref_rseqc_bed= "/data/bnf/dev/sima/rnaSeq_fus/data/RseQC/hg38.HouseKeepingGenes.nochr.bed"
params.ref_rseqc_bed = "/data/bnf/dev/sima/rnaSeq_fus/data/RseQC/Homo_sapiens.GRCh38.79.bed"

jaffa_file = file("/opt/conda/envs/CMD-RNASEQFUS/share/jaffa-1.09-1/JAFFA_direct.groovy")
fusion_report_file = file("/data/bnf/dev/sima/rnaSeq_fus/bin/fusion_classifier_report.Rmd")

/* Set running tool falgs */
/* QC tools */
params.qc = true
params.star_inedx = true
params.star = true
params.fastqscreen = false
params.fastqscreen_genomes = true //This flag shows that the if config file for fastqscreen already exists.  
params.qualimap = false
params.bodyCov = true
params.provider =false
params.combine = false

/* Fusion identification tools */
params.fusion = true
params.star_fusion = false
params.fusioncatcher = false
params.jaffa = false

/* Reads quantification tool */
params.quant = true

/* Other flags */
params.singleEnd= false


/* Define channels */
Channel
        .fromFilePairs( params.reads )
        .ifEmpty { error "Cannot find any reads matching: ${params.reads}" }
        .into {read_files_star_fusion; read_files_fusioncatcher; read_files_jaffa; read_files_star; read_files_star_align; read_files_salmon; read_files_fastqscreen}
	

genome_fasta_ch = Channel.fromPath(params.genome_fasta)

Channel
	.fromPath(params.genome_gtf)
	.into{gtf_star_index;gtf38_qualimap}

//Channel
//	.fromPath(params.genome_gtf38)
//	.set{gtf38_qualimap}

//config_ch = Channel.fromPath(params.config)
ref_RseQC_ch= Channel.fromPath(params.ref_rseqc_bed) 

//Provider channels
bed_ch= Channel.fromPath(params.ref_bed)
bedXy_ch =Channel.fromPath(params.ref_bedXy)


star_fusion_ref = Channel
            .fromPath(params.star_fusion_ref)
            .ifEmpty { exit 1, "Star-Fusion reference directory not found!" }

fusionCatcher_ref = Channel
			.fromPath(params.fusionCatcher_ref)
			.ifEmpty { exit 1, "Fusioncatcher reference directory not found!" }


ref_file_salmon = Channel 
			.fromPath(params.ref_salmon)
			.ifEmpty { exit 1, " Reference file/directory not found!" }


/* Part1: QC */
process build_star_index {

	publishDir "${params.outdir}/star_refGenome_index", mode:'copy'
	cpus = 8
	when:
	params.qc || params.star_inedx
	input :
	file (fasta) from  genome_fasta_ch
	file (gtf) from gtf_star_index 


	output:
	file "star_ref_index" into star_index
	
	script:
	"""
	mkdir star_ref_index
	STAR \\
	--runMode genomeGenerate \\
	--runThreadN ${task.cpus} \\
	--sjdbGTFfile ${gtf} \\
	--genomeDir star_ref_index/ \\
	--genomeFastaFiles ${fasta} 
	"""	
}

process star_alignment{
	
	tag "$name"
	publishDir "${params.outdir}/${name}/star", mode :'copy'
	cpus = 8
	when:
	params.qc || params.star


	input:
	set val(name), file (reads) from read_files_star_align
	file (index_files) from  star_index
	//file  gtf2 from gtf_alignment_ch
	
	output:
	set file("Log.final.out"), file ('*.bam') into star_aligned
	//file ".out" into alignment_logs
	file "SJ.out.tab"
	file "Log.out" into star_log
	file "Aligned.sortedByCoord.out.bam" into aligned_bam, star_sort_bam , star_sort_bam_1, star_sort_bam_2
	file "Log.final.out" into star_logFinalOut_ch
	script: 
	"""
	STAR --genomeDir ${index_files} \\
	--readFilesIn ${reads} \\
	--runThreadN ${task.cpus} \\
	--outSAMtype BAM SortedByCoordinate  \\
	--readFilesCommand zcat \\
	--genomeLoad LoadAndKeep \\
	--limitBAMsortRAM 10000000000
	"""
	//other options: --sjdbGTFfile ${gtf2} \\ --twopassMode Basic \\
}

process SamBamBa {
	tag "$smpl_id"
	publishDir "${params.outdir}/${smpl_id}/star", mode: 'copy'
	when:
	params.qc || params.star
	input:
	file (reads_bam) from aligned_bam
	
	output:
	file "Aligned.sortedByCoord.out.bam.bai"  into star_sort_bai

	script:
	"""
	sambamba index --show-progress -t 8 $reads_bam 
	"""
}


if (params.fastqscreen_genomes) {
    Channel
        .fromPath(params.genome_conf)
        .ifEmpty { exit 1, "Fastqscreen genome config file not found: ${params.genome_conf}" }
        .set {fastq_screen_config_ch}
	} 
else {
	process fastqscreen_getGenome{ 
		
		publishDir "/data/bnf/dev/sima/rnaSeq_fus/data/fastqScreen", mode: 'copy'
		
		output :
		file "*" into output_ch
		file "fastq_screen.conf" into fastq_screen_config_ch
		script:
		"""
		fastq_screen --get_genomes
		"""
	}

}
process fastqscreen{ 
	errorStrategy 'ignore'
	cpus = 8
	publishDir "${params.outdir}/${name}/qc/fastqscreen" , mode :'copy'
	tag "$name"
	when:
	params.fastqscreen || params.qc 

	input:
	set val(name), file(reads) from read_files_fastqscreen
	file (config) from fastq_screen_config_ch
	output:
	file '*.{html,png,txt}' into fastq_screen_ch

	script:
	"""
	fastq_screen --conf $config --aligner bowtie2 --force ${reads[0]}   
	"""
}


process qualimap {
	tag  "$smpl_id"
	publishDir "${params.outdir}/${smpl_id}/qc/qualimap", mode :'copy'
	errorStrategy 'ignore'
	//when :
	//params.qc || params.qualimap

	input:
	file (bam_f) from star_sort_bam
	file (gtf_qualimap) from gtf38_qualimap

	output:
	file '*' into qualimap_ch

	script:
	"""
	export JAVA_OPTS='-Djava.io.tmpdir=/data/tmp'
	qualimap --java-mem-size=12G rnaseq -bam ${bam_f} -gtf ${gtf_qualimap} -pe -outdir . 
	"""

}

	
process rseqc_genebody_coverage {
	tag "$smpl_id"
	publishDir "${params.outdir}/${smpl_id}/qc/genebody_cov", mode:'copy'
	//errorStrategy 'ignore'
	when:
	params.qc || params.bodyCov
	input :
	file (ref_bed) from  ref_RseQC_ch
	file (bam_f) from star_sort_bam_1
	output:
	//file '*.pdf' into gene_bodyCov_ch
	file '*' into bodyCov_output_ch
	file '*.geneBodyCoverage.txt' into gene_bodyCov_ch
	script:
	"""
	geneBody_coverage.py -i ${bam_f} -r ${ref_bed} -o ${smpl_id}
	"""
}


process provider{
	tag "$smpl_id"
	publishDir "${params.outdir}/${smpl_id}/qc/provider" , mode:'copy'
	errorStrategy 'ignore'
	when:
	params.qc || params.provider
	input:
	file (bam_f) from star_sort_bam_2
	file (bed_f) from bed_ch
	file (bedXy_f) from bedXy_ch	
	
	output:
	file "*.genotypes" into provider_output_ch

	script:
	prefix = "output_provider"
	"""
	provider.pl  --out ${prefix} --bed ${bed_f} --bam ${bam_f} --bedxy ${bedXy_f}
	"""
}


	
/* Part2 : fusion identification */


process star_fusion{
	errorStrategy 'ignore'
    tag "$name"
    cpus 8  
    publishDir "${params.outdir}/${name}/fusion/StarFusion", mode: 'copy'

    when:
    params.star_fusion || params.fusion 

    input:
    set val(name), file(reads) from read_files_star_fusion
    //file star_index_star_fusion
    file (reference) from star_fusion_ref

    output:
    file '*fusion_predictions.tsv' optional true into star_fusion_fusions
    file '*.{tsv,txt}' into star_fusion_output

    script:
    //def avail_mem = task.memory ? "--limitBAMsortRAM ${task.memory.toBytes() - 100000000}" : ''
    option = params.singleEnd ? "--left_fq ${reads[0]}" : "--left_fq ${reads[0]} --right_fq ${reads[1]}"
    //def extra_params = params.star_fusion_opt ? "${params.star_fusion_opt}" : ''
    """
    STAR-Fusion \\
        --genome_lib_dir ${reference} \\
        ${option}\\
        --CPU ${task.cpus} \\
        --output_dir .  --verbose_level 2
    """
	// optins: --FusionInspector validate >> error
}

process fusioncatcher {

    tag "$name"
    cpus 4  
    publishDir "${params.outdir}/${name}/fusion/FusionCatcher", mode: 'copy'

    when: params.fusioncatcher || params.fusion

    input:
    set val(name), file(reads) from read_files_fusioncatcher
    file (data_dir) from fusionCatcher_ref

    output:
    file 'final-list_candidate-fusion-genes.txt' optional true into fusioncatcher_fusions
	file 'final-list_candidate-fusion-genes.hg19.txt' into final_list_fusionCatcher_ch
    file '*.{txt,zip,log}' into fusioncatcher_output

    script:
    option = params.singleEnd ? reads[0] : "${reads[0]},${reads[1]}"
    //def extra_params = params.fusioncatcher_opt ? "${params.fusioncatcher_opt}" : ''
    """
    fusioncatcher \\
        -d ${data_dir} \\
        -i ${option} \\
        --threads ${task.cpus} \\
        -o . 
    """
}

/* filter_aml_fusions.pl */
// /data/bnf/scripts/filter_aml_fusions.pl /data/bnf/premap/rnaseq/6192-11_0.fusioncatcher.folder > /data/bnf/premap/rnaseq/6192-11_0.fusioncatcher.xls

process jaffa {
	//errorStrategy 'ignore'
    tag "$name"
    publishDir  "${params.outdir}/${name}/fusion/jaffa", mode: 'copy'

	when:
	params.jaffa || params.fusion
    input:
    set val(name), file(reads) from  read_files_jaffa
    //file groovy from ch_jaffa_direktgroovy
    output:
    file '*.{fasta,csv}' into jaffa_output
    
    script:
    """
    bpipe run -p  genome=hg38 -p refBase="/data/bnf/dev/sima/rnaSeq_fus/data/hg_files/hg38/"  $jaffa_file  ${reads[0]} ${reads[1]}  
    """
}


/*Part3 : Expression quantification */

process create_refIndex{
	cpus = 8
	publishDir "${params.outdir}/salmon_ref_Index", mode:'copy'
	when:
	params.quant 
	input:
	file (ref) from ref_file_salmon 
    file (decoys) from decoys_file              

	output:
	file 'ref_index' into ref_index_ch

	script:
	"""
	salmon  index  --threads 8  -t $ref -d $decoys -i ref_index
	"""  
	}
process quant{
	tag "$name"
	publishDir "${params.outdir}/${name}", mode:'copy'
	cpus = 8
	when:
	params.quant 
	input:
	set val(name), file (reads) from read_files_salmon
	file (index) from ref_index_ch	

	output:
	file  'quant'  into transcripts_quant_ch
	file 'quant/libParams/flenDist.txt' into flendist_ch
	file 'quant/quant.sf' into quant_ch
	script:
	"""
	salmon quant --threads $task.cpus -i $index -l A -1 ${reads[0]} -2 ${reads[1]} --validateMappings -o 'quant'

	"""

}

/* Combine QC files */

process postaln_qc_rna{
	//errorStrategy 'ignore'
	publishDir "${params.outdir}/${smpl_id}/rsults" , mode:'copy'
	
	when:
	params.combine 

	input:
	file (star_final) from star_logFinalOut_ch
	file (fusion) from final_list_fusionCatcher_ch
	file (geneCov) from gene_bodyCov_ch
	file (provIder) from provider_output_ch
	file (flendist) from flendist_ch
	
	output:
	file "${smpl_id}.STAR.rnaseq_QC" into final_out 
	//--flendist
	script:
	"""
	postaln_qc_rna.R  --star ${star_final} --fusion ${fusion} --id '${smpl_id}' --genebody ${geneCov}  --provider ${provIder} --flendist ${flendist} > '${smpl_id}.STAR.rnaseq_QC'
	"""
} 

/* Register to CMD 
process register_to_CMD{
	publishDir "${params.outdir}/${smpl_id}/rsults" , mode:'copy'
	input:
	file (final_QC) from final_out
	output:
	file '*' into  registering_ch
	script:
	"""
	register_sample.pl --run-folder /data/NextSeq1/181121_NB501697_0089_AHFGY3AFXY --sample-id ${smpl_id} --assay rnaseq-fusion --qc  ${final_QC}
	"""
	}
// Create fusion report  
process fusion_report{

	publishDir "${params.outdir}/${smpl_id}/rsults" , mode:'copy'
	input:
	file quant from quant_ch
	output:
	file "${smpl_id}.STAR.fusionreport.html" into report
	script:
	"""
	Rscript -e "rmarkdown::render('${fusion_report_file}', params=list(sampleid= '${smpl_id}',quant_in=${quant},out_json='STAR.fusionreport',quantmethod='salmon'),output_file='${smpl_id}.STAR.fusionreport.html')"
	"""
}
*/

/* Prepare and upload to Coyote */




