.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(haven);library(jsonlite)})
RAW<-'/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1';BASE<-'outputs/year_extension_20261008_v01'
for(scope in c('prepandemic','latest','pooled')) {
 ROOT<-file.path(RAW,scope);O<-file.path(BASE,scope);d<-readRDS(file.path(ROOT,'derived/analysis_frame.rds'))
 wr<-function(x,n)write.csv(x,file.path(O,paste0(n,'.csv')),row.names=FALSE,na='')
# Re-read only official fields used in the original model; do not trust cached eligibility.
validation<-list();raws<-list()
catalog<-read.csv(file.path(BASE,'cycle_catalog.csv'),na.strings=NULL)
for(ci in seq_len(nrow(catalog))) {
 cy<-catalog[ci,];yr<-cy$year;if(!yr %in% d$year)next
 suf<-cy$suffix;z<-NULL
 for(mod in c('DEMO','MCQ','SMQ','BMX')) {
  t<-as.data.frame(read_xpt(file.path(RAW,'data',yr,paste0(cy$prefix,mod,suf,'.xpt'))));names(t)<-toupper(names(t));stopifnot(!anyDuplicated(t$SEQN))
  cols<-switch(mod,DEMO=c('SEQN','RIDAGEYR','RIAGENDR','RIDRETH1','DMDEDUC2','INDFMPIR','SDMVSTRA','SDMVPSU',cy$weight),MCQ=c('SEQN','MCQ010','MCQ160A',if(yr<2009)'MCQ190' else if(yr==2009)'MCQ191' else 'MCQ195'),SMQ=c('SEQN','SMQ020','SMQ040'),BMX=c('SEQN','BMXBMI'))
  t<-t[,cols,drop=FALSE];t[]<-lapply(t,as.numeric)
  z<-if(is.null(z))t else merge(z,t,by='SEQN',all.x=TRUE,sort=FALSE)
 }
 s<-d[d$year==yr,];z<-z[match(s$SEQN,z$SEQN),];stopifnot(identical(z$SEQN,s$SEQN))
 for(v in setdiff(names(z),'SEQN'))stopifnot(isTRUE(all.equal(z[[v]],s[[v]],check.attributes=FALSE)))
 w<-z[[cy$weight]]*if(scope=='latest')1 else cy$duration/if(scope=='prepandemic')21.2 else 23.2
 typ<-z[[if(yr<2009)'MCQ190' else if(yr==2009)'MCQ191' else 'MCQ195']]
 ra<-ifelse(z$MCQ160A==2,0,ifelse(z$MCQ160A==1 & typ==if(yr<2011)1 else 2,1,NA))
 asthma<-ifelse(z$MCQ010==1,1,ifelse(z$MCQ010==2,0,NA))
 smoke<-ifelse(z$SMQ020==2,'never',ifelse(z$SMQ020==1 & z$SMQ040==3,'former',ifelse(z$SMQ020==1 & z$SMQ040 %in% c(1,2),'current',NA)))
 pre<-z$RIDAGEYR>=20 & z$RIDAGEYR<=79 & is.finite(w)&w>0&!is.na(z$SDMVSTRA)&!is.na(z$SDMVPSU)&!is.na(ra)&!is.na(asthma)
 cc<-pre & z$RIAGENDR %in% 1:2 & z$RIDRETH1 %in% 1:5 & z$DMDEDUC2 %in% 1:5 & is.finite(z$INDFMPIR)&z$INDFMPIR>=0&z$INDFMPIR<=5 & is.finite(z$BMXBMI)&z$BMXBMI>0&!is.na(smoke)
 pre[is.na(pre)]<-FALSE;cc[is.na(cc)]<-FALSE
 stopifnot(identical(pre,s$pre_covariate),identical(cc,s$eligible),max(abs(w-s$analysis_weight),na.rm=TRUE)<1e-10)
 validation[[length(validation)+1]]<-data.frame(year=yr,source_fields_equal=TRUE,pre_equal=TRUE,cc_equal=TRUE,n=sum(cc))
}
wr(do.call(rbind,validation),'source_reconstruction');rm(z,s,t)


 write_json(list(verdict='pass',cycles=length(validation),n=sum(d$eligible),scope='independent raw reread; eligibility and weighting reconstruction'),file.path(O,'independent_input_validation.json'),auto_unbox=TRUE,pretty=TRUE)
 cat(scope,'independent input PASS',sum(d$eligible),'\n')
}
