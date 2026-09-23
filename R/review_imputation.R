args<-commandArgs(trailingOnly=TRUE)
.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages(library(mice))
z<-readRDS(file.path(args[1],'derived/v03/imputations.rds'));imp<-z$imp
summaries<-list()
for(v in c('education','pir','smoke')) {
  chains<-t(imp$chainMean[v,,]) # chain x iteration; diagnostic on imputation summaries
  n<-ncol(chains);within<-mean(apply(chains,1,var));between<-n*var(rowMeans(chains))
  rhat<-sqrt(((n-1)/n*within+between/n)/within)
  summaries[[v]]<-data.frame(variable=v,summary_rhat=rhat,
                             first_half_mean=mean(chains[,1:floor(n/2)]),
                             last_half_mean=mean(chains[,(floor(n/2)+1):n]),within_chain_sd=sqrt(within))
}
write.csv(do.call(rbind,summaries),'results/qc/imputation_stability.csv',row.names=FALSE)
png('results/qc/imputation_trace.png',width=1500,height=950,res=150)
print(plot(imp,c('education','pir','smoke')));dev.off()
print(do.call(rbind,summaries))
print(head(imp$loggedEvents,6))
cat('Event count',nrow(imp$loggedEvents),'\n')
cat('Unique event descriptions:\n');print(unique(imp$loggedEvents$out))
# Technical boundaries only; convergence and event patterns still need review.
for(i in seq_len(imp$m)) {
 d<-complete(imp,i)
 stopifnot(!anyNA(d[c('education','pir','smoke')]),all(d$pir>=0 & d$pir<=5),
           all(as.character(d$education)%in%as.character(1:5)),all(as.character(d$smoke)%in%as.character(0:2)))
}
cat('PASS: imputed domains and categories\n')
