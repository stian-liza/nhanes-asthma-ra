# Publication-style report figures from reviewed aggregate results only.
.libPaths(c(normalizePath('.Rlib'),.libPaths()))
suppressPackageStartupMessages(library(ggplot2))
dir.create('results/figures/report_v03',recursive=TRUE,showWarnings=FALSE)
font<-'Heiti SC'; blue<-'#17638D'; orange<-'#B65328'
savefig<-function(p,name,w,h){
  ggsave(paste0('results/figures/report_v03/',name,'.png'),p,width=w,height=h,dpi=320,bg='white')
  grDevices::quartz(type='pdf',file=paste0('results/figures/report_v03/',name,'.pdf'),width=w,height=h)
  print(p);dev.off()
}
base<-theme_minimal(base_size=11,base_family=font)+
  theme(plot.title=element_text(size=13,face='bold'),panel.grid.minor=element_blank(),
        panel.grid.major.y=element_blank(),plot.margin=margin(8,8,8,8))
flow<-read.csv('results/qc/sample_flow.csv')
a<-flow[flow$analysis=='primary'&flow$cycle=='all',]
b<-flow[flow$analysis=='ever20'&flow$cycle=='all',]
stopifnot(a$adult_n-a$ra_unknown_n-a$joint_known_n==142,
          b$adult_n-b$ra_unknown_n-b$joint_known_n==37)
nodes<-data.frame(x=rep(c(2.5,7.5),each=4),y=rep(c(8.6,6.5,4.4,2.1),2),
 text=c('主分析  2001-2018\n九周期源样本 91,351人','20岁及以上成人\n50,201人',
        '两病状态均明确\n45,558人','协变量多重插补主模型 45,558人\n完整病例敏感性 41,486人',
        '补充分析  1999-2018\n十周期源样本 101,316人','20岁及以上成人\n55,081人',
        '两病状态均明确\n50,018人','协变量多重插补主模型 50,018人\n完整病例敏感性 45,270人'))
ar<-data.frame(x=rep(c(2.5,7.5),each=3),y=rep(c(7.97,5.87,3.77),2),
              yend=rep(c(7.14,5.04,2.74),2))
notes<-data.frame(x=rep(c(2.5,7.5),each=3),y=rep(c(7.57,5.50,3.24),2),
 text=c('排除不足20岁者 41,150人','依次排除 RA未知 4,501人\n及当前哮喘未知 142人',
        '只插补协变量\n协变量不完整 4,072人',
        '排除不足20岁者 46,235人','依次排除 RA未知 5,026人\n及曾患哮喘未知 37人',
        '只插补协变量\n协变量不完整 4,748人'))
p<-ggplot()+geom_rect(data=nodes,aes(xmin=x-2.15,xmax=x+2.15,ymin=y-.62,ymax=y+.62),
                      fill='#F4F7F9',color='#9EAFBA',linewidth=.5)+
  geom_text(data=nodes,aes(x,y,label=text),family=font,size=3.5,lineheight=1.25)+
  geom_segment(data=ar,aes(x=x,xend=x,y=y,yend=yend),color='#8B969F',
               arrow=grid::arrow(length=grid::unit(.10,'inches')))+
  geom_label(data=notes,aes(x,y,label=text),family=font,size=2.95,lineheight=1.12,
             fill='white',linewidth=0,label.padding=grid::unit(.12,'lines'))+
  annotate('text',x=5,y=.67,label='疾病未知不插补；排除人数按顺序统计，避免重复计数',family=font,size=3.3,color='#424B52')+
  coord_cartesian(xlim=c(0,10),ylim=c(.2,9.5),expand=FALSE)+theme_void()
savefig(p,'figure1_flow',7.4,5.0)

m<-read.csv('results/tables/standardized_prevalence.csv')
plot<-m[m$metric%in%c('RA','nonRA'),]
plot$period<-factor(plot$analysis,levels=c('primary_MI','ever20_MI'),
  labels=c('主分析  当前哮喘\n2001-2018','补充分析  曾患哮喘\n1999-2018'))
plot$group<-factor(plot$metric,levels=c('nonRA','RA'),labels=c('非RA','RA'))
plot$text<-sprintf('%.2f%%',100*plot$estimate)
p<-ggplot(plot,aes(group,estimate*100,color=group))+
  geom_errorbar(aes(ymin=lower*100,ymax=upper*100),width=.12,linewidth=.7)+geom_point(size=3)+
  geom_text(aes(y=upper*100+1.6,label=text),family=font,size=3.4,show.legend=FALSE)+
  facet_wrap(~period,nrow=1)+scale_color_manual(values=c('非RA'=blue,'RA'=orange),guide='none')+
  scale_y_continuous(limits=c(0,28),breaks=seq(0,25,5),labels=function(z)paste0(z,'%'))+
  labs(x=NULL,y='标准化哮喘患病比例')+base+
  theme(strip.text=element_text(size=11,face='bold'),panel.grid.major.x=element_blank())
savefig(p,'figure2_prevalence',7.4,2.8)

x<-read.csv('results/tables/association_models.csv')
ids<-c('primary_MI','ever20_MI','primary_CC','no_arthritis_MI','current_never_MI','linear_age_MI',
       'unknown_type_as_nonRA_CC','unknown_type_as_RA_CC')
labels<-c('当前哮喘 主分析','曾患哮喘 补充分析','当前哮喘 完整病例',
          '对照限定为无任何关节炎','当前哮喘对从未哮喘','年龄采用线性调整',
          '未知类型全部归非RA','未知类型全部归RA')
z<-x[x$model=='M2',];z<-z[match(ids,z$analysis),];stopifnot(!anyNA(z$estimate))
z$y<-rev(seq_len(nrow(z)));z$label<-labels;z$primary<-z$analysis=='primary_MI'
z$value<-sprintf('%.2f (%.2f-%.2f)',z$estimate,z$lower,z$upper)
p<-ggplot(z,aes(estimate,y,color=primary))+
  geom_vline(xintercept=1,linetype=2,color='#858585',linewidth=.5)+
  geom_segment(aes(x=lower,xend=upper,yend=y),linewidth=.65)+geom_point(size=2.7)+
  geom_text(aes(x=.28,label=label),family=font,hjust=0,size=3.05,show.legend=FALSE)+
  geom_text(aes(x=4.0,label=format(n,big.mark=',',trim=TRUE)),family=font,hjust=.5,size=3.05,show.legend=FALSE)+
  geom_text(aes(x=6.0,label=value),family=font,hjust=.5,size=3.05,show.legend=FALSE)+
  annotate('text',x=.28,y=9,label='分析',family=font,hjust=0,size=3.15,fontface='bold')+
  annotate('text',x=4.0,y=9,label='人数',family=font,size=3.15,fontface='bold')+
  annotate('text',x=6.0,y=9,label='优势比及95%置信区间',family=font,size=3.15,fontface='bold')+
  scale_color_manual(values=c('FALSE'='#40484D','TRUE'=blue),guide='none')+
  scale_x_log10(limits=c(.27,8),breaks=c(1,1.5,2,3),labels=c('1','1.5','2','3'))+
  scale_y_continuous(limits=c(.5,9.5),breaks=NULL)+
  labs(x='调整后患病优势比  对数刻度',y=NULL)+base+
  theme(panel.grid.major.x=element_blank(),axis.text.x=element_text(size=9),axis.title.x=element_text(size=10))
savefig(p,'figure3_associations',7.4,3.35)
cat('PASS: three report figures generated from reviewed aggregate tables\n')
