.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages(library(ggplot2))
x<-read.csv('results/tables/association_models.csv')
x<-x[x$model=='M2',]
labels<-c(primary_MI='Primary: current asthma, 2001-2018 (MI)',
          primary_CC='Current asthma: complete cases',
          ever20_MI='Supplement: ever asthma, 1999-2018 (MI)',
          ever18_MI='Ever asthma, 2001-2018 (MI)',
          no_arthritis_MI='Comparison group: no arthritis of any type',
          current_never_MI='Current versus never asthma',
          from2003_MI='Restrict to 2003-2018',linear_age_MI='Use linear age adjustment',
          unknown_type_as_nonRA_CC='Unknown arthritis type assigned non-RA (CC)',
          unknown_type_as_RA_CC='Unknown arthritis type assigned RA (CC)')
forest<-function(data,name,title,height) {
  data$label<-factor(data$label,levels=rev(data$label))
  data$highlight<-data$analysis=='primary_MI'
  p<-ggplot(data,aes(estimate,label,color=highlight))+
    geom_vline(xintercept=1,linetype=2,color='grey50')+
    geom_errorbar(aes(xmin=lower,xmax=upper),orientation='y',width=.13,linewidth=.6)+
    geom_point(size=2.5)+scale_color_manual(values=c('FALSE'='#444444','TRUE'='#0072B2'),guide='none')+
    scale_x_log10(breaks=c(1,1.5,2,2.5,3),limits=c(.95,3.4))+
    labs(title=title,x='Adjusted prevalence odds ratio (95% confidence interval)',y=NULL,
         caption='MI: multiple imputation; CC: complete cases. Self-reported diagnoses; cross-sectional associations.')+
    theme_bw(base_size=11)+theme(panel.grid.minor=element_blank(),plot.title=element_text(size=13),
                                plot.caption=element_text(size=9,hjust=0))
  ggsave(paste0('results/figures/',name,'.png'),p,width=11,height=height,dpi=180)
  ggsave(paste0('results/figures/',name,'.pdf'),p,width=11,height=height)
}
main<-x[match(names(labels),x$analysis),];main$label<-unname(labels)
forest(main,'key_associations','Self-reported rheumatoid arthritis and asthma: main checks',6)
loo<-rbind(x[x$analysis=='primary_MI',],x[grepl('^omit_',x$analysis),])
loo$label<-sapply(loo$analysis,function(a){
  if(a=='primary_MI')return('Primary: all nine cycles')
  y<-as.integer(sub('omit_([0-9]+)_MI','\\1',a));paste('Omit',paste0(y,'-',y+1))
})
forest(loo,'leave_one_cycle_out','Current asthma: leave-one-cycle-out checks',6)
