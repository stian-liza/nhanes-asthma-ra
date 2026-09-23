.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages({library(survey);library(mice);library(splines)})
# Evaluate only the analysis functions; never start the real-data analysis from a test.
for(e in parse('R/analysis.R')) {
  if(is.call(e) && identical(e[[1]],as.name('<-')) && is.call(e[[3]]) &&
     identical(e[[3]][[1]],as.name('function'))) eval(e)
}
options(survey.lonely.psu='fail')
synthetic<-expand.grid(person=1:100,psu=1:2,stratum=1:8)
synthetic$ra<-as.numeric(synthetic$person>50)
synthetic$y<-as.numeric((synthetic$ra==0 & synthetic$person<=5) |
                         (synthetic$ra==1 & synthetic$person>90))
synthetic$w<-100
des<-svydesign(ids=~psu,strata=~stratum,weights=~w,nest=TRUE,data=synthetic)
fit<-fit_one(des,'M0',margins=TRUE)
stopifnot(abs(exp(fit$q)-2.25)<1e-7,
          max(abs(fit$margin_q-c(.1,.2,.1)))<1e-7)
# Survey residual df must enter MI pooling, not the participant count.
pooled<-pool_scalar(c(.5,.51,.49),c(.04,.04,.04),dfcom=12,exponentiate=TRUE)
stopifnot(pooled$df<12,abs(pooled$estimate-exp(.5))<1e-10,
          pooled$lower<pooled$estimate,pooled$upper>pooled$estimate)
cat('PASS: synthetic OR, standardized probabilities, and finite-design MI pooling\n')
