load -run ./coverage/scope/irq_unit
report -summary -metrics code -both -inst *... -out code_summary.txt
report -detail -metrics code -both -inst *... -out code_details.txt
report -summary -metrics covergroup -both -inst *... -out functional_summary.txt
report -detail -html -metrics code -inst *... -out code_html
exit
