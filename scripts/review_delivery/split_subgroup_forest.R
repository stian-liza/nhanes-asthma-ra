# Re-layout saved estimates only; no model fitting. No figure titles or numbers.
args<-commandArgs(trailingOnly=TRUE)
if(length(args)) .libPaths(c(args[1],.libPaths()))
suppressPackageStartupMessages({library(ggplot2);library(ragg)})
source_dir<-'outputs/year_extension_20261008_v01/prepandemic'
out<-'outputs/figure_revision_20261008_v01'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
systemfonts::register_font('NHANES_CJK',plain='/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
sub<-read.csv(file.path(source_dir,'subgroups.csv'))
ints<-read.csv(file.path(source_dir,'interaction_tests.csv'))
labels<-c('20-39'='20—39 岁','40-59'='40—59 岁','60-79'='60—79 岁','Male'='男性','Female'='女性')
for(group in c('agegroup','sex')) {
 d<-sub[sub$subgroup_variable==group,]
 stopifnot(nrow(d)==if(group=='agegroup')3 else 2,all(d$status=='estimable'))
 d$y<-rev(seq_len(nrow(d)));d$label<-paste0(labels[d$subgroup],'   n = ',format(d$n,big.mark=',',trim=TRUE))
 d$estimate_text<-sprintf('%.2f（%.2f–%.2f）',d$OR,d$lower,d$upper)
 top<-nrow(d)+.68
 p<-ggplot(d,aes(y=y))+
  annotate('segment',x=1,xend=1,y=.35,yend=nrow(d)+.28,linetype='dashed',color='gray50',linewidth=.45)+
  geom_segment(aes(x=lower,xend=upper,yend=y),linewidth=.65)+
  geom_point(aes(x=OR),shape=15,size=3.3,color='#204F70')+
  geom_text(aes(x=4.65,label=estimate_text),hjust=0,size=3.9,family='NHANES_CJK')+
  annotate('text',x=.79,y=top,label=sprintf('交互 P = %.4f',ints$p[ints$variable==group]),hjust=0,size=3.9,family='NHANES_CJK')+
  annotate('text',x=4.65,y=top,label='OR（95% CI）',hjust=0,size=3.9,family='NHANES_CJK')+
  scale_x_log10(breaks=c(1,1.5,2,3,4),labels=c('1.0','1.5','2.0','3.0','4.0'))+
  scale_y_continuous(breaks=d$y,labels=d$label,expand=expansion(mult=0))+
  coord_cartesian(xlim=c(.78,4.2),ylim=c(.35,top+.25),clip='off')+
  labs(x='曾患哮喘的调整后 OR（对数刻度）',y=NULL)+
  theme_classic(base_family='NHANES_CJK',base_size=11.5)+
  theme(axis.line.y=element_blank(),axis.ticks.y=element_blank(),
        axis.text=element_text(color='black'),axis.text.y=element_text(margin=margin(r=12)),
        axis.title.x=element_text(margin=margin(t=9)),plot.margin=margin(10,160,10,10))
 name<-if(group=='agegroup')'age_subgroups' else 'sex_subgroups'
 height<-if(group=='agegroup')3.5 else 2.85
 ggsave(file.path(out,paste0(name,'.png')),p,width=8.4,height=height,dpi=300,device=ragg::agg_png,bg='white')
 q<-p+theme(text=element_text(family='Arial Unicode MS'))
 for(i in seq_along(q$layers)) if(!is.null(q$layers[[i]]$aes_params$family)) q$layers[[i]]$aes_params$family<-'Arial Unicode MS'
 quartz(file=file.path(out,paste0(name,'.pdf')),type='pdf',width=8.4,height=height,family='Arial Unicode MS');print(q);dev.off()
}
file.copy(file.path(source_dir,'subgroups.csv'),file.path(out,'source_subgroups.csv'),overwrite=TRUE)
file.copy(file.path(source_dir,'interaction_tests.csv'),file.path(out,'source_interaction_tests.csv'),overwrite=TRUE)
cat('Two separate forests generated from saved estimates; no model changes.\n')
