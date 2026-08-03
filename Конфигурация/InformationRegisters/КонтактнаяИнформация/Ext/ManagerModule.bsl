Функция ПолучитьДляТерминала(Запрос, НомерТелефона, TransactionId,ReceiptNumber, QueryType = "check") Экспорт  
	
	ResultCode = "21";
	ResultStatus = "Error";
	ResultMessage = "Заказы не найдены";
	OrdersCount = 0;
	OrdersXML = "";
	
	Попытка
		
		Если QueryType = "check" Тогда
			
			Заказы = Документы.ЗаказПокупателя.ПолучитьЗаказыДляОплатыТерминалом(НомерТелефона);
			
			Если Заказы <> Неопределено И Заказы.Количество() > 0 Тогда
				
				ResultCode = "0";
				ResultStatus = "Success";
				ResultMessage = "";
				OrdersCount = Заказы.Количество();
				
				OrdersXML = "<Orders>";
				
				Для Каждого СтрЗаказ Из Заказы Цикл
					OrdersXML = OrdersXML 
						+ Документы.ЗаказПокупателя.ПолучитьОтветПоЗакамДляОплатыВТерминале(СтрЗаказ, НомерТелефона);
				КонецЦикла;
				
				OrdersXML = OrdersXML + "</Orders>";
				
			КонецЕсли;
			
		ИначеЕсли QueryType = "pay" Тогда
			
			OrderId = Запрос.ПараметрыЗапроса.Получить("OrderId");
			Amount = Запрос.ПараметрыЗапроса.Получить("Amount");
			
			Если ПустаяСтрока(OrderId) Тогда
				
				ResultCode = "21";
				ResultStatus = "Error";
				ResultMessage = "Не передан OrderId";
				
			ИначеЕсли ПустаяСтрока(Amount) Тогда
				
				ResultCode = "21";                                 
				ResultStatus = "Error";
				ResultMessage = "Не передана сумма оплаты";
				
			Иначе
				
				OrderGUID = Новый УникальныйИдентификатор(OrderId);
				ЗаказСсылка = Документы.ЗаказПокупателя.ПолучитьСсылку(OrderGUID);
				
				Если ЗаказСсылка = Неопределено Или ЗаказСсылка.Пустая() Тогда
					
					ResultCode = "21";
					ResultStatus = "Error";
					ResultMessage = "Заказ не найден";
					
				Иначе
					
					// проверка суммы
					СуммаОплаты = Число(СтрЗаменить(Amount, ".", ","));
					
					Если СуммаОплаты <= 0 Тогда
						
						ResultCode = "241";
						ResultStatus = "Error";
						ResultMessage = "Некорректная сумма оплаты";
						
					Иначе
						
						// проверка дублей TransactionId
						// TODO: позже лучше проверять по отдельному регистру платежей терминала
						// Пока проверяем по комментарию документа оплаты
						
						ЗапросДубль = Новый Запрос;
						ЗапросДубль.Текст =
						"ВЫБРАТЬ ПЕРВЫЕ 1
						|	ПКО.Ссылка
						|ИЗ
						|	Документ.ПриходныйКассовыйОрдер КАК ПКО
						|ГДЕ
						|	ПКО.Комментарий ПОДОБНО &Комментарий";
						
						ЗапросДубль.УстановитьПараметр("Комментарий", "%" + TransactionId + "%");
						
						ВыборкаДубль = ЗапросДубль.Выполнить().Выбрать();
						
						Если ВыборкаДубль.Следующий() Тогда
							
							ResultCode = "0";
							ResultStatus = "Success";
							ResultMessage = "Платеж уже был принят ранее";
							
						Иначе
							
												
							Комментарий = 
							"Оплата через терминал. TransactionId: " + Строка(TransactionId)  
							+ "; ReceiptNumber: " + Строка(ReceiptNumber)
							+ "; OrderId: " + Строка(OrderId)
							+ "; Account: " + Строка(НомерТелефона);

							
							
							ПКО = Документы.ПриходныйКассовыйОрдер.СоздатьПКО(ЗаказСсылка, СуммаОплаты, Комментарий, "Г00000031", Ложь);
													
														
							Попытка
								ПКО.Записать(РежимЗаписиДокумента.Проведение);
								
								ResultCode = "0";
								ResultStatus = "Success";
								ResultMessage = "Платеж принят";
								
							Исключение
								
								ResultCode = "2";
								ResultStatus = "Error";
								ResultMessage = "Ошибка создания оплаты: " + ОписаниеОшибки();
								
							КонецПопытки;
							
						КонецЕсли;
						
					КонецЕсли;					
				КонецЕсли;
				
			КонецЕсли;			
		Иначе
			
			ResultCode = "299";
			ResultStatus = "Error";
			ResultMessage = "Неподдерживаемый QueryType";
			
		КонецЕсли;
		
	Исключение
		
		ResultCode = "2";
		ResultStatus = "Error";
		ResultMessage = ОписаниеОшибки();
		OrdersCount = 0;
		OrdersXML = "";
		
	КонецПопытки;
	
	XML = 
	"<?xml version=""1.0"" encoding=""UTF-8""?>" + Символы.ПС +
	"<Response>" +
	"<TransactionId>" + XMLСтрока(TransactionId) + "</TransactionId>" +
	"<ResultCode>" + XMLСтрока(ResultCode) + "</ResultCode>" +
	"<ResultStatus>" + XMLСтрока(ResultStatus) + "</ResultStatus>" +
	"<ResultMessage>" + XMLСтрока(ResultMessage) + "</ResultMessage>" +
	"<OrdersCount>" + XMLСтрока(Строка(OrdersCount)) + "</OrdersCount>" +
	OrdersXML +
	"<Comment></Comment>" +
	"</Response>";
	
	Возврат XML;
	
КонецФункции 
