args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)>=1)
root <- normalizePath(args[1]); out <- file.path(root,'derived/v03')
.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages({library(survey);library(mice);library(splines)})
options(survey.lonely.psu='fail')
d <- read.csv(file.path(out,'persons.csv'),na.strings=c('','NA'))
for (v in c('ra_unknown_type','ra_conflict','no_arthritis','asthma_conflict','smoke_conflict'))
  d[[v]] <- tolower(as.character(d[[v]]))=='true'
base <- d[d$cycle>=2001 & d$WTINT2YR>0,]
des <- svydesign(ids=~SDMVPSU,strata=~SDMVSTRA,weights=~w_primary,nest=TRUE,data=base)
dom <- subset(des,age>=20 & !is.na(ra) & !is.na(current))
knots <- as.numeric(coef(svyquantile(~age,dom,c(1/3,2/3),ci=FALSE)))
stopifnot(length(unique(knots))==2)
dir.create('config',showWarnings=FALSE)
jsonlite::write_json(list(age_knots=knots,age_boundary=c(20,80),seed=20260923,
                         imputations=30,iterations=10,primary='2001-2018 current asthma',
                         supplementary='1999-2018 ever asthma',design_df=degf(dom)),
                    'config/analysis_lock.json',auto_unbox=TRUE,pretty=TRUE)
ix <- which(d$age>=20 & !is.na(d$ra) & !is.na(d$ever))
b <- d[ix,]
aux <- ifelse(b$ever==0,'never',ifelse(is.na(b$current),'ever_current_unknown',
                                   ifelse(b$current==1,'current','former')))
age_basis <- ns(b$age,knots=knots,Boundary.knots=c(20,80))
mi <- data.frame(ra=b$ra,asthma_aux=factor(aux),age1=age_basis[,1],age2=age_basis[,2],
                 age3=age_basis[,3],sex=factor(b$sex),race=factor(b$race),
                 education=factor(b$education,levels=1:5),pir=b$pir,
                 smoke=factor(b$smoke,levels=0:2),cycle=factor(b$cycle),
                 stratum=factor(b$SDMVSTRA),psu=factor(b$SDMVPSU),logweight=log(b$w_ever20))
method <- setNames(rep('',ncol(mi)),names(mi)); method[c('education','pir','smoke')]<-'pmm'
pred <- make.predictorMatrix(mi);pred[!names(method)%in%c('education','pir','smoke'),]<-0
write.csv(pred,'results/qc/imputation_predictors.csv')
# All cycles and all strata are included; ridge/QR handles nested dummy coding.
cat('IMPUTE_START',format(Sys.time()),'n',nrow(mi),'\n');flush.console()
imp <- mice(mi,m=30,maxit=10,method=method,predictorMatrix=pred,seed=20260923,
            printFlag=TRUE,donors=5,remove.collinear=FALSE,remove.constant=FALSE)
saveRDS(list(imp=imp,index=ix,age_knots=knots),file.path(out,'imputations.rds'))
events <- imp$loggedEvents
if(is.null(events)) events<-data.frame(note='none')
write.csv(events,'results/qc/imputation_events.csv',row.names=FALSE)
trace <- as.data.frame.table(imp$chainMean,responseName='mean');names(trace)[1:3]<-c('variable','iteration','chain')
write.csv(trace,'results/qc/imputation_chain_means.csv',row.names=FALSE)
variance <- as.data.frame.table(imp$chainVar,responseName='variance')
write.csv(variance,'results/qc/imputation_chain_variances.csv',row.names=FALSE)
pdf('results/qc/imputation_trace.pdf',width=10,height=7)
print(plot(imp,c('education','pir','smoke')));dev.off()
distribution<-list()
for(v in c('education','pir','smoke')) {
  miss<-is.na(mi[[v]])
  z<-unlist(lapply(seq_len(imp$m),function(i) as.numeric(as.character(complete(imp,i)[[v]][miss]))))
  obs<-as.numeric(as.character(mi[[v]][!miss]))
  distribution[[v]]<-data.frame(variable=v,source=c('observed','imputed'),
     n=c(length(obs),length(z)),mean=c(mean(obs),mean(z)),sd=c(sd(obs),sd(z)),
     min=c(min(obs),min(z)),max=c(max(obs),max(z)))
}
write.csv(do.call(rbind,distribution),'results/qc/imputation_distributions.csv',row.names=FALSE)
cat('IMPUTE_END',format(Sys.time()),'\n')
